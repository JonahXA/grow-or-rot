--[[
	WeatherService — one server-wide state machine, broadcast to everyone.

	It is the cheapest live-service layer available: a weighted random pick on a
	timer plus a RemoteEvent. It does three jobs that are hard to get any other
	way at zero players:

	  1. It moves where the optimal harvest sits, so the core decision cannot be
	     solved once and memorised. That is the single biggest threat to this
	     game's lifespan.
	  2. It creates shared moments — everyone in the server sees Rainbow at once.
	  3. It gives a reason to come back, which is a D1 retention lever.

	Weather is global and authoritative on the server. The client is told what it
	is and when it ends, and nothing more; the deltas stay server-side so the
	exact curve is not shipped to exploiters.
]]

local Players = game:GetService("Players")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local Telemetry = require(script.Parent.Telemetry)

local WeatherService = {}

local current = Config.Weather.States[1]
local endsAt = 0

local weatherRemote: RemoteEvent? = nil

local function totalWeight(): number
	local sum = 0
	for _, state in Config.Weather.States do
		sum += state.weight
	end
	return sum
end

local function pickState()
	-- Weighted pick. Deliberately allows repeating the same weather twice in a
	-- row: forcing variety would make the sequence predictable, and predictable
	-- weather defeats the point of having it.
	local roll = math.random() * totalWeight()
	local running = 0
	for _, state in Config.Weather.States do
		running += state.weight
		if roll <= running then
			return state
		end
	end
	return Config.Weather.States[1]
end

function WeatherService.getCurrent()
	return current
end

--[[ What the client is allowed to know: the label and the countdown. ]]
function WeatherService.getView()
	return {
		id = current.id,
		displayName = current.displayName,
		endsAt = endsAt,
	}
end

function WeatherService.mutationDelta(): number
	return current.mutationDelta
end

function WeatherService.rotDelta(): number
	return current.rotDelta
end

local function broadcast()
	if not weatherRemote then
		return
	end
	weatherRemote:FireAllClients(WeatherService.getView())
end

function WeatherService.pushTo(player: Player)
	if not weatherRemote then
		return
	end
	weatherRemote:FireClient(player, WeatherService.getView())
end

function WeatherService.start()
	weatherRemote = Remotes.get("WeatherChanged") :: RemoteEvent

	task.spawn(function()
		while true do
			current = pickState()
			local duration =
				math.random(Config.Weather.MinDurationSeconds, Config.Weather.MaxDurationSeconds)
			endsAt = os.time() + duration
			broadcast()

			-- Logged per transition rather than per player: this is a world
			-- event, and tagging it to whoever happened to be online would make
			-- the dashboard read as if weather were a player action.
			local anyone = Players:GetPlayers()[1]
			if anyone then
				Telemetry.custom(anyone, "WeatherChanged", 1, {
					weather = current.id,
					durationSeconds = duration,
					playersOnline = #Players:GetPlayers(),
				})
			end

			task.wait(duration)
		end
	end)
end

return WeatherService
