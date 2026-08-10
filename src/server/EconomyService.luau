--[[
	EconomyService — the only code allowed to change a player's coin balance,
	and the shared rate limiter for every gameplay remote.

	Everything here is server-authoritative. Remotes carry intent ("harvest plot
	3"), never value ("give me 4200 coins"), so there is nothing for a client to
	forge. The server owns every number.

	The rate limiter is the actual anti-exploit. A hooked client can fire a
	remote thousands of times a second; without a floor that is a free action
	printer. It is centralised here so a new remote cannot accidentally ship
	without one.
]]

local Players = game:GetService("Players")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)

local DataService = require(script.Parent.DataService)
local Telemetry = require(script.Parent.Telemetry)

local EconomyService = {}

local lastAction: { [Player]: number } = {}
local rejectedActions: { [Player]: number } = {}
local suspicionLogged: { [Player]: boolean } = {}

--[[
	Call at the top of every remote handler. Returns false when the caller is
	going too fast, in which case the handler must return without doing work.

	Deliberately one shared budget across all actions rather than per-remote:
	an exploiter alternating between two remotes should not get double the rate.
]]
function EconomyService.allowAction(player: Player): boolean
	local now = os.clock()
	local previous = lastAction[player]
	if previous and (now - previous) < Config.Economy.ActionCooldownSeconds then
		local count = (rejectedActions[player] or 0) + 1
		rejectedActions[player] = count
		if count >= Config.Economy.SuspiciousRejectThreshold and not suspicionLogged[player] then
			suspicionLogged[player] = true
			Telemetry.custom(player, "SuspiciousActionRate", count)
			warn(
				string.format(
					"[Economy] %s exceeded action rate limit %d times",
					player.Name,
					count
				)
			)
		end
		return false
	end
	lastAction[player] = now
	return true
end

--[[
	The single mutation point for currency.

	`reason` and `sku` flow straight into the economy analytics event, which is
	what makes the Creator Dashboard economy chart readable later. If you add a
	new way to gain or spend coins, give it a distinct reason string — otherwise
	you lose the ability to tell harvest income from purchased income, which is
	exactly the split that reveals whether the loop or the shop is carrying the
	game.
]]
function EconomyService.addCoins(
	player: Player,
	amount: number,
	reason: string,
	sku: string?
): boolean
	local profile = DataService.get(player)
	if not profile then
		return false
	end
	if amount == 0 then
		return true
	end

	if amount < 0 and profile.coins + amount < 0 then
		return false -- insufficient funds; caller decides how to surface it
	end

	profile.coins += amount
	if amount > 0 then
		profile.totalCoinsEarned += amount
	end

	Telemetry.economy(player, amount > 0, "Coins", amount, profile.coins, reason, sku)
	return true
end

function EconomyService.canAfford(player: Player, amount: number): boolean
	local profile = DataService.get(player)
	return profile ~= nil and profile.coins >= amount
end

function EconomyService.start()
	Players.PlayerRemoving:Connect(function(player)
		lastAction[player] = nil
		rejectedActions[player] = nil
		suspicionLogged[player] = nil
	end)
end

return EconomyService
