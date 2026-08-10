--[[
	World — builds the (deliberately plain) environment in code.

	Generated at runtime rather than committed as a .rbxl so the repo stays
	diffable text. That trade stops being worth it the moment there is real art;
	at that point the place file becomes the source of truth for Workspace and
	Rojo syncs only scripts into it.

	Each player gets their own farm plot models, parented under a per-player
	folder. Plots are visual only — every authoritative fact about a crop lives
	in the profile, and this file just renders what the server already decided.
]]

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)

local World = {}

--[[
	Fires (player, plotIndex) when someone uses a plot's prompt.

	A BindableEvent rather than a direct call into PlotService, because
	PlotService already requires World for rendering. Inverting one direction
	keeps the dependency one-way and avoids a circular require.
]]
World.PlotPromptTriggered = Instance.new("BindableEvent")

local FARM_ROOT = "Farms"
local PLOT_SPACING = 12

-- Colour per mutation count, offset by one: index 1 is unmutated. A pure array
-- rather than a [0]-plus-array mixed table, which iterates and serializes in
-- surprising ways. Beyond the end, the last colour repeats rather than erroring.
local MUTATION_COLORS = {
	Color3.fromRGB(96, 176, 84),
	Color3.fromRGB(140, 210, 90),
	Color3.fromRGB(226, 190, 62),
	Color3.fromRGB(150, 200, 235),
	Color3.fromRGB(240, 150, 220),
	Color3.fromRGB(255, 110, 110),
}

local function ensureBaseplate()
	if Workspace:FindFirstChild("Baseplate") then
		return
	end
	local base = Instance.new("Part")
	base.Name = "Baseplate"
	base.Size = Vector3.new(512, 20, 512)
	base.Position = Vector3.new(0, -10, 0)
	base.Anchored = true
	base.TopSurface = Enum.SurfaceType.Smooth
	base.BrickColor = BrickColor.new("Bright green")
	base.Material = Enum.Material.Grass
	base.Parent = Workspace
end

local function ensureSpawn()
	if Workspace:FindFirstChildOfClass("SpawnLocation") then
		return
	end
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "Spawn"
	spawn.Size = Vector3.new(12, 1, 12)
	spawn.Position = Vector3.new(0, 0.5, 24)
	spawn.Anchored = true
	spawn.BrickColor = BrickColor.new("Institutional white")
	spawn.Parent = Workspace
end

local function farmRoot(): Folder
	local existing = Workspace:FindFirstChild(FARM_ROOT)
	if existing then
		return existing :: Folder
	end
	local folder = Instance.new("Folder")
	folder.Name = FARM_ROOT
	folder.Parent = Workspace
	return folder
end

--[[
	Builds one plot: a soil pad, a crop part that scales with growth, and a
	billboard readout. The billboard is the whole UI for a plot — value, risk and
	stage all live above the crop, so the decision is legible from the world
	without opening a menu. That directly serves time-to-first-action.
]]
local function buildPlot(parent: Folder, index: number)
	local model = Instance.new("Model")
	model.Name = "Plot" .. tostring(index)

	local soil = Instance.new("Part")
	soil.Name = "Soil"
	soil.Size = Vector3.new(8, 1, 8)
	soil.Position = Vector3.new((index - 1) * PLOT_SPACING, 0.5, 0)
	soil.Anchored = true
	soil.BrickColor = BrickColor.new("Reddish brown")
	soil.Material = Enum.Material.Ground
	soil.TopSurface = Enum.SurfaceType.Smooth
	soil.Parent = model

	local crop = Instance.new("Part")
	crop.Name = "Crop"
	crop.Size = Vector3.new(2, 1, 2)
	crop.Position = soil.Position + Vector3.new(0, 1, 0)
	crop.Anchored = true
	crop.CanCollide = false
	crop.Material = Enum.Material.Grass
	crop.Color = World.mutationColor(0)
	crop.Transparency = 1 -- empty plot
	crop.Parent = model

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "Prompt"
	prompt.ActionText = "Plant"
	prompt.ObjectText = "Plot " .. tostring(index)
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 14
	prompt.RequiresLineOfSight = false
	prompt.Parent = soil

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "Readout"
	billboard.Size = UDim2.fromScale(10, 3)
	billboard.StudsOffset = Vector3.new(0, 5, 0)
	billboard.AlwaysOnTop = true
	billboard.Parent = crop

	local label = Instance.new("TextLabel")
	label.Name = "Text"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = "Empty"
	label.TextScaled = true
	label.Font = Enum.Font.GothamBold
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0.3
	label.Parent = billboard

	--[[
		One prompt does the contextually correct thing — plant when empty,
		harvest when ripe, nothing while growing. A single button that is always
		the right button is what keeps time-to-first-action under 30 seconds,
		which is the pattern every breakout game on the platform shares.
	]]
	prompt.Triggered:Connect(function(triggeringPlayer: Player)
		World.PlotPromptTriggered:Fire(triggeringPlayer, index)
	end)

	model.Parent = parent
	return model
end

function World.buildFarm(player: Player): Folder
	local root = farmRoot()
	local existing = root:FindFirstChild(player.Name)
	if existing then
		existing:Destroy()
	end

	local farm = Instance.new("Folder")
	farm.Name = player.Name

	for index = 1, Config.Grow.MaxPlots do
		buildPlot(farm, index)
	end

	farm.Parent = root
	return farm
end

function World.mutationColor(mutations: number): Color3
	return MUTATION_COLORS[math.clamp(mutations + 1, 1, #MUTATION_COLORS)]
end

--[[
	Renders a player's plots from the same PlotView the client receives.

	Deliberately server-side rather than each client drawing its own farm: farms
	are visible to everyone in the server, and client-side rendering would show
	other players nothing but empty soil. Seeing someone else's Prismatic crop
	sitting at nine push ticks is the closest this game gets to a social hook,
	and it costs nothing to keep.
]]
function World.render(player: Player, plotViews)
	local root = Workspace:FindFirstChild(FARM_ROOT)
	local farm = root and root:FindFirstChild(player.Name)
	if not farm then
		return
	end

	for _, view in plotViews do
		local model = farm:FindFirstChild("Plot" .. tostring(view.index))
		if model then
			local crop = model:FindFirstChild("Crop") :: Part?
			local soil = model:FindFirstChild("Soil")
			local prompt = soil and soil:FindFirstChild("Prompt") :: ProximityPrompt?
			local label = crop
				and crop:FindFirstChild("Readout")
				and crop.Readout:FindFirstChild("Text") :: TextLabel?

			if crop and label then
				if not view.seedId then
					crop.Transparency = 1
					crop.Size = Vector3.new(2, 1, 2)
					label.Text = "Empty"
					label.TextColor3 = Color3.fromRGB(200, 200, 200)
					if prompt then
						prompt.Enabled = true
						prompt.ActionText = "Plant"
					end
				elseif not view.isRipe then
					local remaining = math.max(0, view.ripeAt - os.time())
					crop.Transparency = 0.25
					crop.Size = Vector3.new(2, 2, 2)
					crop.Color = World.mutationColor(view.mutations)
					label.Text =
						string.format("%s\nGrowing  %ds", view.displayName or "Crop", remaining)
					label.TextColor3 = Color3.fromRGB(200, 230, 200)
					if prompt then
						prompt.Enabled = false
					end
				else
					crop.Transparency = 0
					crop.Size = Vector3.new(3, 3 + view.mutations * 0.4, 3)
					crop.Color = World.mutationColor(view.mutations)
					local tier = view.mutationName and (view.mutationName .. "  ") or ""
					label.Text = string.format(
						"%s%d coins\nrot risk %d%%",
						tier,
						view.value,
						math.floor(view.rotChance * 100 + 0.5)
					)
					-- Colour the readout by risk. The decision has to be
					-- readable at a glance from across the farm, not by parsing
					-- a percentage.
					label.TextColor3 = if view.rotChance >= 0.35
						then Color3.fromRGB(255, 120, 120)
						elseif view.rotChance >= 0.2 then Color3.fromRGB(255, 210, 120)
						else Color3.fromRGB(180, 255, 180)
					if prompt then
						prompt.Enabled = true
						prompt.ActionText = "Harvest"
					end
				end
			end
		end
	end
end

function World.start()
	ensureBaseplate()
	ensureSpawn()

	Players.PlayerAdded:Connect(function(player)
		World.buildFarm(player)
	end)
	for _, player in Players:GetPlayers() do
		World.buildFarm(player)
	end

	Players.PlayerRemoving:Connect(function(player)
		local farm = farmRoot():FindFirstChild(player.Name)
		if farm then
			farm:Destroy()
		end
	end)

	Lighting.Ambient = Color3.fromRGB(120, 120, 130)
	Lighting.OutdoorAmbient = Color3.fromRGB(150, 150, 160)
end

return World
