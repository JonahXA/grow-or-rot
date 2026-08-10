--[[
	PlotService — the game.

	Owns planting, growth, the push-your-luck rolls, and harvesting. Plot state
	lives inside the player's profile, so persistence comes free from DataService
	and a crop survives a server restart.

	Three rules govern everything here:

	  1. THE SERVER OWNS EVERY NUMBER. Remotes carry intent ("harvest plot 3"),
	     never value. The client is sent a precomputed value and rot chance, not
	     the formula — shipping the curve would hand exploiters the exact odds and
	     let a hooked client decide what a crop is worth.

	  2. GROWTH HAPPENS OFFLINE, PUSHING DOES NOT. Ripeness is derived from
	     `plantedAt`, so crops mature while you are away. `lastPushAt` is reset on
	     profile load, which freezes the risk rolls. A returning player finds a
	     field of ripe crops holding at guaranteed value — a field of choices
	     rather than a field of loss. That is a D1 retention decision.

	  3. RISK RISES, REWARD COMPOUNDS. Rot chance climbs linearly per tick while
	     value multiplies. That gap is the entire reason pushing is tempting, and
	     tuning it is tuning the game.
]]

local Players = game:GetService("Players")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)
local MonetizationService = require(script.Parent.MonetizationService)
local Telemetry = require(script.Parent.Telemetry)
local WeatherService = require(script.Parent.WeatherService)
local World = require(script.Parent.World)

local PlotService = {}

-- Last seed the player explicitly chose, so the in-world prompt keeps planting
-- what they picked instead of reverting to basic every time.
local selectedSeed: { [Player]: string } = {}

local stateRemote: RemoteEvent? = nil
local plotEventRemote: RemoteEvent? = nil

-- Per-session first-time funnel flags. Not persisted: these drive the onboarding
-- funnel, which is a per-visit journey.
local firstPlant: { [Player]: boolean } = {}
local firstHarvest: { [Player]: boolean } = {}

-- ============================================================
-- Pure helpers
-- ============================================================

local function seedConfig(seedId: string?)
	if not seedId then
		return nil
	end
	return Config.Seeds[seedId]
end

local function emptyPlot()
	return {
		seedId = nil,
		plantedAt = 0,
		mutations = 0,
		pushTicks = 0,
		lastPushAt = 0,
		insuranceUsed = false,
	}
end

local function ripeAt(plot): number
	local seed = seedConfig(plot.seedId)
	if not seed then
		return 0
	end
	return plot.plantedAt + seed.growTime
end

local function isRipe(plot, now: number): boolean
	return plot.seedId ~= nil and now >= ripeAt(plot)
end

--[[ Coins this crop would pay right now. Mutations stack multiplicatively. ]]
local function currentValue(plot): number
	local seed = seedConfig(plot.seedId)
	if not seed then
		return 0
	end
	return math.floor(seed.baseValue * (Config.Grow.MutationMultiplier ^ plot.mutations))
end

--[[
	Chance the NEXT push tick destroys this crop.

	Takes no player deliberately. Rot Insurance absorbs the outcome once rather
	than reducing the roll, so ownership must not appear here — folding it in
	would misrepresent what the pass does and quietly desync the number shown on
	the billboard from the number actually rolled.
]]
local function rotChance(plot): number
	local seed = seedConfig(plot.seedId)
	if not seed then
		return 0
	end
	local chance = Config.Grow.RotChanceBase
		+ (Config.Grow.RotChancePerTick * plot.pushTicks)
		+ (seed.rotChanceBonus or 0)
		+ WeatherService.rotDelta()

	return math.clamp(chance, 0, Config.Grow.RotChanceMax)
end

local function mutationChance(plot, player: Player): number
	local seed = seedConfig(plot.seedId)
	if not seed then
		return 0
	end
	local chance = seed.mutationChance + WeatherService.mutationDelta()
	if MonetizationService.hasPass(player, "SeedLuck") then
		chance += 0.10
	end
	return math.clamp(chance, 0, 0.95)
end

local function mutationName(count: number): string?
	if count <= 0 then
		return nil
	end
	local names = Config.Grow.MutationNames
	return names[math.min(count, #names)]
end

-- ============================================================
-- Profile shape
-- ============================================================

--[[
	Guarantees the plots array matches the player's owned plot count. Called on
	load and after any plot purchase, so an ExtraPlot grant does not need to know
	anything about array shape.
]]
local function ensurePlots(profile)
	local wanted =
		math.clamp(profile.upgrades.plotCount or Config.Grow.StartingPlots, 1, Config.Grow.MaxPlots)
	profile.upgrades.plotCount = wanted

	while #profile.plots < wanted do
		table.insert(profile.plots, emptyPlot())
	end
	-- Never shrink below what exists. Losing a plot would silently destroy a
	-- crop the player is mid-decision on.
	while #profile.plots > wanted and #profile.plots > 0 do
		local last = profile.plots[#profile.plots]
		if last.seedId then
			break
		end
		table.remove(profile.plots)
	end
end

--[[
	The offline freeze. Ripeness is derived from plantedAt so growth continued
	while away; resetting lastPushAt to now means zero push rolls happened.
]]
local function thawOnLoad(profile)
	local now = os.time()
	for _, plot in profile.plots do
		if plot.seedId then
			plot.lastPushAt = now
		end
	end
end

-- ============================================================
-- Client view
-- ============================================================

function PlotService.buildState(player: Player)
	local profile = DataService.get(player)
	if not profile then
		return nil
	end
	local now = os.time()

	local plots = {}
	for index, plot in profile.plots do
		local seed = seedConfig(plot.seedId)
		local ripe = isRipe(plot, now)
		table.insert(plots, {
			index = index,
			seedId = plot.seedId,
			displayName = seed and seed.displayName or nil,
			ripeAt = ripeAt(plot),
			isRipe = ripe,
			mutations = plot.mutations,
			mutationName = mutationName(plot.mutations),
			pushTicks = plot.pushTicks,
			nextPushAt = ripe and (plot.lastPushAt + Config.Grow.PushTickSeconds) or 0,
			value = currentValue(plot),
			rotChance = ripe and rotChance(plot) or 0,
		})
	end

	return {
		coins = profile.coins,
		plots = plots,
		seeds = profile.seeds,
		weather = WeatherService.getView(),
		passes = {
			rotInsurance = MonetizationService.hasPass(player, "RotInsurance"),
			seedLuck = MonetizationService.hasPass(player, "SeedLuck"),
			autoHarvest = MonetizationService.hasPass(player, "AutoHarvest"),
		},
	}
end

function PlotService.pushState(player: Player)
	local state = PlotService.buildState(player)
	if not state then
		return
	end
	if stateRemote then
		stateRemote:FireClient(player, state)
	end
	World.render(player, state.plots)
end

local function fireEvent(player: Player, payload)
	if plotEventRemote then
		plotEventRemote:FireClient(player, payload)
	end
end

-- ============================================================
-- Actions
-- ============================================================

function PlotService.plant(player: Player, plotIndex: unknown, seedId: unknown)
	if not EconomyService.allowAction(player) then
		return
	end
	if type(plotIndex) ~= "number" or type(seedId) ~= "string" then
		return
	end

	local profile = DataService.get(player)
	if not profile then
		return
	end

	local plot = profile.plots[plotIndex]
	if not plot or plot.seedId then
		return -- out of range, or already occupied
	end

	local seed = seedConfig(seedId)
	if not seed then
		return
	end

	-- Free seeds are unlimited; anything with a cost must be in inventory. This
	-- guarantees a player can always plant something and never soft-locks by
	-- spending their last coins.
	if seed.cost > 0 then
		local held = profile.seeds[seedId] or 0
		if held <= 0 then
			return
		end
		profile.seeds[seedId] = held - 1
	end

	selectedSeed[player] = seedId

	local now = os.time()
	plot.seedId = seedId
	plot.plantedAt = now
	plot.mutations = 0
	plot.pushTicks = 0
	plot.insuranceUsed = false
	-- Zero means "not started"; the tick loop starts the push clock at ripeness.
	plot.lastPushAt = 0

	if not firstPlant[player] then
		firstPlant[player] = true
		Telemetry.onboardingStep(player, Telemetry.OnboardingStep.FirstPlant)
		Telemetry.funnelStep(player, Telemetry.OnboardingStep.FirstPlant)
	end

	Telemetry.custom(player, "Planted", 1, { seed = seedId })
	PlotService.pushState(player)
end

function PlotService.harvest(player: Player, plotIndex: unknown)
	if not EconomyService.allowAction(player) then
		return
	end
	if type(plotIndex) ~= "number" then
		return
	end

	local profile = DataService.get(player)
	if not profile then
		return
	end

	local plot = profile.plots[plotIndex]
	if not plot or not plot.seedId then
		return
	end
	if not isRipe(plot, os.time()) then
		return -- not ready; the client should not have offered the option
	end

	local value = currentValue(plot)
	local seedId = plot.seedId
	local mutations = plot.mutations
	local ticks = plot.pushTicks

	EconomyService.addCoins(player, value, "Harvest", seedId)

	profile.stats.totalHarvested += 1
	if value > profile.stats.bestSingleHarvest then
		profile.stats.bestSingleHarvest = value
	end

	profile.plots[plotIndex] = emptyPlot()

	if not firstHarvest[player] then
		firstHarvest[player] = true
		Telemetry.onboardingStep(player, Telemetry.OnboardingStep.FirstHarvest)
		Telemetry.funnelStep(player, Telemetry.OnboardingStep.FirstHarvest)
	end

	--[[
		pushTicks is the payload that matters here. It is how many times the
		player chose to gamble before banking, which is the closest thing this
		game has to a measure of whether the decision is working. If the
		distribution collapses to a single spike, the curve has been solved and
		the loop is dead.
	]]
	Telemetry.custom(player, "Harvested", value, {
		seed = seedId,
		mutations = mutations,
		pushTicks = ticks,
		weather = WeatherService.getCurrent().id,
	})

	fireEvent(player, { kind = "harvested", index = plotIndex, value = value })
	PlotService.pushState(player)
end

function PlotService.buySeed(player: Player, seedId: unknown)
	if not EconomyService.allowAction(player) then
		return
	end
	if type(seedId) ~= "string" then
		return
	end

	local profile = DataService.get(player)
	if not profile then
		return
	end

	local seed = seedConfig(seedId)
	if not seed or seed.cost <= 0 then
		return
	end
	if not EconomyService.addCoins(player, -seed.cost, "SeedPurchase", seedId) then
		return -- insufficient funds
	end

	profile.seeds[seedId] = (profile.seeds[seedId] or 0) + 1
	Telemetry.custom(player, "SeedBought", 1, { seed = seedId })
	PlotService.pushState(player)
end

-- ============================================================
-- The push tick
-- ============================================================

local function resolvePush(player: Player, profile, plotIndex: number, plot)
	local now = os.time()
	plot.lastPushAt = now

	local valueAtRisk = currentValue(plot)

	if math.random() < rotChance(plot) then
		-- Rot. Insurance absorbs the outcome once per crop rather than reducing
		-- the odds, so the pass is a safety net and not an immortality button.
		if MonetizationService.hasPass(player, "RotInsurance") and not plot.insuranceUsed then
			plot.insuranceUsed = true
			plot.pushTicks += 1
			fireEvent(player, { kind = "saved", index = plotIndex, value = valueAtRisk })
			Telemetry.custom(player, "RotInsuranceSaved", valueAtRisk, { seed = plot.seedId })
			PlotService.pushState(player)
			return
		end

		profile.stats.totalRotted += 1
		if valueAtRisk > profile.stats.biggestLoss then
			profile.stats.biggestLoss = valueAtRisk
		end

		Telemetry.custom(player, "Rotted", valueAtRisk, {
			seed = plot.seedId,
			mutations = plot.mutations,
			pushTicks = plot.pushTicks,
			weather = WeatherService.getCurrent().id,
		})

		profile.plots[plotIndex] = emptyPlot()
		fireEvent(player, { kind = "rotted", index = plotIndex, value = valueAtRisk })
		PlotService.pushState(player)
		return
	end

	plot.pushTicks += 1

	if math.random() < mutationChance(plot, player) then
		plot.mutations += 1
		fireEvent(player, {
			kind = "mutated",
			index = plotIndex,
			mutations = plot.mutations,
			mutationName = mutationName(plot.mutations),
			value = currentValue(plot),
		})
	end

	PlotService.pushState(player)
end

local function tickPlayer(player: Player)
	local profile = DataService.get(player)
	if not profile then
		return
	end
	local now = os.time()

	for index, plot in profile.plots do
		if plot.seedId and isRipe(plot, now) then
			-- Start the push clock at ripeness, not at planting, so the first
			-- gamble is a full tick after the crop becomes bankable.
			if plot.lastPushAt == 0 then
				plot.lastPushAt = math.max(ripeAt(plot), now - Config.Grow.PushTickSeconds)
			end

			if (now - plot.lastPushAt) >= Config.Grow.PushTickSeconds then
				resolvePush(player, profile, index, plot)
			end
		end
	end
end

-- ============================================================
-- In-world prompt
-- ============================================================

--[[
	One prompt, contextual action. Plant when the plot is empty, harvest when
	it's ripe, ignore while growing.

	Seed choice falls back gracefully: the last seed you deliberately planted, or
	the default if you've run out of it. A player who buys one Volatile seed and
	spends it should not then find the prompt silently doing nothing.
]]
local function onPrompt(player: Player, plotIndex: number)
	local profile = DataService.get(player)
	if not profile then
		return
	end
	local plot = profile.plots[plotIndex]
	if not plot then
		return
	end

	if not plot.seedId then
		local wanted = selectedSeed[player] or Config.DefaultSeed
		local seed = seedConfig(wanted)
		if not seed or (seed.cost > 0 and (profile.seeds[wanted] or 0) <= 0) then
			wanted = Config.DefaultSeed
		end
		PlotService.plant(player, plotIndex, wanted)
	elseif isRipe(plot, os.time()) then
		PlotService.harvest(player, plotIndex)
	end
end

-- ============================================================
-- Monetization grants
-- ============================================================

local function grantExtraPlot(player: Player): boolean
	local profile = DataService.get(player)
	if not profile then
		return false
	end
	if profile.upgrades.plotCount >= Config.Grow.MaxPlots then
		return false -- refuse rather than take money for nothing
	end
	profile.upgrades.plotCount += 1
	ensurePlots(profile)
	PlotService.pushState(player)
	return true
end

local function grantInstantGrow(player: Player): boolean
	local profile = DataService.get(player)
	if not profile then
		return false
	end
	local now = os.time()
	local affected = 0
	for _, plot in profile.plots do
		if plot.seedId and not isRipe(plot, now) then
			plot.plantedAt = now - seedConfig(plot.seedId).growTime
			affected += 1
		end
	end
	if affected == 0 then
		return false -- nothing to ripen; do not consume the purchase
	end
	PlotService.pushState(player)
	return true
end

-- ============================================================
-- Lifecycle
-- ============================================================

function PlotService.start()
	stateRemote = Remotes.get("StateChanged") :: RemoteEvent
	plotEventRemote = Remotes.get("PlotEvent") :: RemoteEvent

	MonetizationService.registerProductHandler("ExtraPlot", grantExtraPlot)
	MonetizationService.registerProductHandler("InstantGrow", grantInstantGrow)
	MonetizationService.setStateRefresh(PlotService.pushState)

	local plantRemote = Remotes.get("Plant") :: RemoteEvent
	plantRemote.OnServerEvent:Connect(PlotService.plant)

	local harvestRemote = Remotes.get("Harvest") :: RemoteEvent
	harvestRemote.OnServerEvent:Connect(PlotService.harvest)

	local buySeedRemote = Remotes.get("BuySeed") :: RemoteEvent
	buySeedRemote.OnServerEvent:Connect(PlotService.buySeed)

	local getState = Remotes.get("GetState") :: RemoteFunction
	getState.OnServerInvoke = function(player: Player)
		-- The client may invoke before the profile finishes loading. Yield
		-- rather than return a zeroed state the client would render as an empty
		-- farm — that reads as data loss to a returning player.
		local deadline = os.clock() + 20
		while not DataService.get(player) and os.clock() < deadline do
			task.wait(0.1)
		end
		return PlotService.buildState(player)
	end

	DataService.ProfileLoaded.Event:Connect(function(player: Player, profile)
		ensurePlots(profile)
		thawOnLoad(profile)
		WeatherService.pushTo(player)
		PlotService.pushState(player)
	end)

	World.PlotPromptTriggered.Event:Connect(onPrompt)

	Players.PlayerRemoving:Connect(function(player)
		firstPlant[player] = nil
		firstHarvest[player] = nil
		selectedSeed[player] = nil
	end)

	-- One second is deliberate. Push ticks are 10s apart, so a 1s loop keeps
	-- resolution well inside the gameplay grain while costing nothing.
	--
	-- Rendering every second regardless of whether anything resolved is what
	-- makes the growth countdown above each plot actually count down; state
	-- pushes alone would leave it frozen between events.
	task.spawn(function()
		while true do
			task.wait(1)
			for _, player in Players:GetPlayers() do
				tickPlayer(player)
				local state = PlotService.buildState(player)
				if state then
					World.render(player, state.plots)
				end
			end
		end
	end)
end

return PlotService
