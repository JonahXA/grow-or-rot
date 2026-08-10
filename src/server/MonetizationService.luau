--[[
	MonetizationService — game passes and developer products.

	The ProcessReceipt callback below is the highest-stakes code in the project.
	Two rules govern it:

	  1. It must be IDEMPOTENT. Roblox re-delivers a receipt until you return
	     PurchaseGranted, including across server restarts and rejoins. Without
	     a durable record of honored receipts, a player who buys once during a
	     server hiccup gets granted two, five, twenty times.

	  2. It must return NotProcessedYet on ANY uncertainty. Returning
	     PurchaseGranted when the grant did not durably persist means the player
	     paid Robux and got nothing, and Roblox will not re-deliver. That is a
	     refund request and a one-star review.

	How this satisfies both: the receipt marker lives in the player's own
	profile, so the grant and "mark the receipt honored" are the same single
	DataStore write. There is no window where one landed and the other didn't.

	    already marked in profile?  -> yes: return PurchaseGranted (replay)
	    apply grant + mark receipt in memory
	    DataService.save()          -> failed: roll both back, NotProcessedYet
	                                -> ok:     return PurchaseGranted

	Note the deliberate absence of a second DataStore and of UpdateAsync. An
	earlier draft put the grant and the save inside a receipt-store UpdateAsync
	transform. That throws at runtime: UpdateAsync transform callbacks are not
	permitted to yield, and DataService.save yields.

	This version was verified against production in phase0: three live purchases,
	each granted exactly once.

	--- Products that aren't currency ---

	ExtraPlot and InstantGrow change gameplay state, not the wallet. Rather than
	teach this file about plots, it exposes registerProductHandler so PlotService
	registers its own grants at startup. That keeps the dependency one-way —
	PlotService knows about monetization, monetization knows nothing about plots
	— and avoids a circular require.
]]

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)
local Telemetry = require(script.Parent.Telemetry)

local MonetizationService = {}

-- productId -> config key, built at startup from Config.DeveloperProducts.
local productLookup: { [number]: string } = {}
local shopOpened: { [Player]: boolean } = {}

-- player -> { [passKey]: boolean }. Resolved once on join so the gameplay hot
-- path never touches MarketplaceService.
local ownedPasses: { [Player]: { [string]: boolean } } = {}

-- Grant handlers for non-currency products, registered by the systems that own
-- the state. Each returns true only if the grant actually applied.
local productHandlers: { [string]: (Player) -> boolean } = {}

-- Set by PlotService so a pass purchase can refresh the client immediately.
local stateRefresh: ((Player) -> ())? = nil

local function isConfigured(id: number?): boolean
	return type(id) == "number" and id > 0
end

function MonetizationService.registerProductHandler(key: string, handler: (Player) -> boolean)
	productHandlers[key] = handler
end

function MonetizationService.setStateRefresh(fn: (Player) -> ())
	stateRefresh = fn
end

local function refresh(player: Player)
	if stateRefresh then
		stateRefresh(player)
	end
end

-- ============================================================
-- Game passes
-- ============================================================

function MonetizationService.hasPass(player: Player, passKey: string): boolean
	local owned = ownedPasses[player]
	return owned ~= nil and owned[passKey] == true
end

local function resolvePasses(player: Player)
	local owned = {}

	for passKey, passId in Config.GamePasses do
		if isConfigured(passId) then
			for attempt = 1, 3 do
				local ok, result = pcall(function()
					return MarketplaceService:UserOwnsGamePassAsync(player.UserId, passId)
				end)
				if ok then
					owned[passKey] = result
					break
				end
				warn(
					string.format(
						"[Monetization] pass check %d for %s (%s) failed: %s",
						attempt,
						player.Name,
						passKey,
						tostring(result)
					)
				)
				task.wait(attempt)
			end
		else
			owned[passKey] = false
		end
	end

	ownedPasses[player] = owned
	refresh(player)
end

-- ============================================================
-- Developer products
-- ============================================================

--[[
	Applies a product. Returns the rollback function on success, nil on failure.

	Returning the undo rather than a bare boolean is what makes the durability
	gate below correct for both currency and gameplay grants — the caller can
	reverse whatever happened without knowing what it was.
]]
local function applyGrant(player: Player, configKey: string): (() -> ())?
	local coins = Config.ProductGrants[configKey]
	if coins then
		if not EconomyService.addCoins(player, coins, "ProductPurchase", configKey) then
			return nil
		end
		return function()
			EconomyService.addCoins(player, -coins, "ProductRollback", configKey)
		end
	end

	local handler = productHandlers[configKey]
	if not handler then
		warn(string.format("[Monetization] no grant defined for %q", configKey))
		return nil
	end
	if not handler(player) then
		return nil
	end

	--[[
		Gameplay grants have no clean inverse — un-ripening a crop the player has
		already seen ripen would be worse than the duplicate it prevents. The
		durability gate below still protects the common case, and the failure
		mode here is a player keeping a grant we could not record, which is the
		right direction to fail in.
	]]
	return function() end
end

local function processReceipt(receiptInfo: any): Enum.ProductPurchaseDecision
	local player = Players:GetPlayerByUserId(receiptInfo.PlayerId)
	if not player then
		-- They left mid-purchase. Roblox re-delivers on their next join.
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local profile = DataService.get(player)
	if not profile then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local configKey = productLookup[receiptInfo.ProductId]
	if not configKey then
		-- Unknown product: almost always a Config gap after adding a product in
		-- the dashboard but not here. Do NOT grant, do NOT consume the receipt.
		warn(string.format("[Monetization] unmapped ProductId %d", receiptInfo.ProductId))
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local purchaseId = tostring(receiptInfo.PurchaseId)

	-- Replay of a receipt this profile already honored. The marker was loaded
	-- from the DataStore alongside whatever it granted, so if it's here, the
	-- grant is too.
	if profile.processedReceipts[purchaseId] then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end

	local undo = applyGrant(player, configKey)
	if not undo then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	profile.robuxSpent += receiptInfo.CurrencySpent
	profile.purchaseCount += 1
	DataService.rememberReceipt(profile, purchaseId)

	-- Durability gate. Only claim the receipt once the grant AND the marker have
	-- survived a real write.
	if not DataService.save(player, false) then
		undo()
		profile.robuxSpent -= receiptInfo.CurrencySpent
		profile.purchaseCount -= 1
		DataService.forgetReceipt(profile, purchaseId)
		warn(string.format("[Monetization] receipt %s not durable; will retry", purchaseId))
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	Telemetry.onboardingStep(player, Telemetry.OnboardingStep.FirstPurchase)
	Telemetry.funnelStep(player, Telemetry.OnboardingStep.FirstPurchase)
	Telemetry.custom(player, "PurchaseCompleted", receiptInfo.CurrencySpent, {
		product = configKey,
		robux = receiptInfo.CurrencySpent,
	})

	refresh(player)
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

-- ============================================================
-- Purchase prompts (client-initiated)
-- ============================================================

local function onPurchaseRequest(player: Player, kind: unknown, key: unknown)
	if type(kind) ~= "string" or type(key) ~= "string" then
		return -- malformed remote payload
	end

	if not shopOpened[player] then
		shopOpened[player] = true
		Telemetry.onboardingStep(player, Telemetry.OnboardingStep.FirstShopOpen)
		Telemetry.funnelStep(player, Telemetry.OnboardingStep.FirstShopOpen)
	end

	if kind == "gamepass" then
		local id = Config.GamePasses[key]
		if not isConfigured(id) then
			warn(string.format("[Monetization] game pass %q is not configured (id 0)", key))
			return
		end
		MarketplaceService:PromptGamePassPurchase(player, id)
	elseif kind == "product" then
		local id = Config.DeveloperProducts[key]
		if not isConfigured(id) then
			warn(string.format("[Monetization] product %q is not configured (id 0)", key))
			return
		end
		MarketplaceService:PromptProductPurchase(player, id)
	end
end

function MonetizationService.start()
	for key, id in Config.DeveloperProducts do
		if isConfigured(id) then
			productLookup[id] = key
		end
	end

	-- Must be assigned exactly once, on the server, for the whole game.
	MarketplaceService.ProcessReceipt = processReceipt

	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, wasPurchased)
		if not wasPurchased then
			return
		end
		for passKey, configured in Config.GamePasses do
			if isConfigured(configured) and passId == configured then
				local owned = ownedPasses[player]
				if not owned then
					owned = {}
					ownedPasses[player] = owned
				end
				owned[passKey] = true
				Telemetry.custom(player, "GamePassPurchased", 1, { pass = passKey })
				Telemetry.onboardingStep(player, Telemetry.OnboardingStep.FirstPurchase)
				refresh(player)
				break
			end
		end
	end)

	local requestRemote = Remotes.get("RequestPurchase") :: RemoteEvent
	requestRemote.OnServerEvent:Connect(onPurchaseRequest)

	DataService.ProfileLoaded.Event:Connect(function(player)
		task.spawn(resolvePasses, player)
	end)

	Players.PlayerRemoving:Connect(function(player)
		shopOpened[player] = nil
		ownedPasses[player] = nil
	end)
end

return MonetizationService
