--[[
	Client bootstrap.

	Responsibilities, and nothing beyond them:
	  - build the HUD
	  - render whatever the server pushes
	  - forward intent (buy this, prompt me for that)

	It does not track coins, compute crop value, decide rot, or judge whether a
	purchase succeeded. Every one of those is a server answer. Planting and
	harvesting are not even here — those run off in-world ProximityPrompts, which
	the server owns end to end.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage.Shared.Remotes)
local HUD = require(script.HUD)

local buySeedRemote = Remotes.get("BuySeed") :: RemoteEvent
local purchaseRemote = Remotes.get("RequestPurchase") :: RemoteEvent
local stateRemote = Remotes.get("StateChanged") :: RemoteEvent
local plotEventRemote = Remotes.get("PlotEvent") :: RemoteEvent
local weatherRemote = Remotes.get("WeatherChanged") :: RemoteEvent
local getState = Remotes.get("GetState") :: RemoteFunction

local hud = HUD.new()
hud:render(nil)

stateRemote.OnClientEvent:Connect(function(state)
	hud:render(state)
end)

weatherRemote.OnClientEvent:Connect(function(weather)
	hud.lastWeather = weather
	hud:renderWeather(weather)
end)

local GREEN = Color3.fromRGB(150, 240, 160)
local GOLD = Color3.fromRGB(255, 214, 66)
local RED = Color3.fromRGB(255, 120, 120)
local BLUE = Color3.fromRGB(150, 200, 255)

plotEventRemote.OnClientEvent:Connect(function(payload)
	if type(payload) ~= "table" then
		return
	end
	if payload.kind == "mutated" then
		hud:toast(
			string.format("%s!  worth %d", payload.mutationName or "Mutated", payload.value),
			GOLD
		)
	elseif payload.kind == "rotted" then
		hud:toast(string.format("Rotted — lost %d", payload.value), RED)
	elseif payload.kind == "saved" then
		hud:toast(string.format("Insurance saved %d", payload.value), BLUE)
	elseif payload.kind == "harvested" then
		hud:toast(string.format("Harvested %d coins", payload.value), GREEN)
	end
end)

hud.buySwift.Activated:Connect(function()
	buySeedRemote:FireServer("swift")
end)

hud.buyVolatile.Activated:Connect(function()
	buySeedRemote:FireServer("volatile")
end)

hud.passRotInsurance.Activated:Connect(function()
	purchaseRemote:FireServer("gamepass", "RotInsurance")
end)

hud.passSeedLuck.Activated:Connect(function()
	purchaseRemote:FireServer("gamepass", "SeedLuck")
end)

hud.passAutoHarvest.Activated:Connect(function()
	purchaseRemote:FireServer("gamepass", "AutoHarvest")
end)

hud.buyPlot.Activated:Connect(function()
	purchaseRemote:FireServer("product", "ExtraPlot")
end)

hud.buyInstantGrow.Activated:Connect(function()
	purchaseRemote:FireServer("product", "InstantGrow")
end)

-- The weather countdown ticks locally off the server-provided end time, so it
-- stays smooth without a remote firing every second.
task.spawn(function()
	while true do
		task.wait(1)
		hud:renderWeather(hud.lastWeather)
	end
end)

-- Initial pull. The server yields until the profile is loaded, so this can take
-- a couple of seconds on a cold DataStore.
task.spawn(function()
	local ok, state = pcall(function()
		return getState:InvokeServer()
	end)
	if ok then
		hud:render(state)
	else
		warn("[GrowOrRot] initial state fetch failed: " .. tostring(state))
	end
end)
