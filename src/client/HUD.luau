--[[
	HUD — coins, weather, shop, and event feedback.

	Deliberately small. The plots themselves are rendered in the world with
	billboards showing value and rot risk, because the core decision should be
	readable while standing in the farm rather than behind a menu. Anything that
	pushes the decision into UI works against time-to-first-action.

	The HUD renders state it is given. It never computes a balance, a crop value
	or a rot chance — the server is the only thing that knows those, and shipping
	the formulas here would hand exploiters the exact curve.
]]

local Players = game:GetService("Players")

local HUD = {}
HUD.__index = HUD

local function corner(parent: Instance, radius: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
end

local function button(text: string, color: Color3, size: UDim2, position: UDim2): TextButton
	local b = Instance.new("TextButton")
	b.Size = size
	b.Position = position
	b.BackgroundColor3 = color
	b.BorderSizePixel = 0
	b.Text = text
	b.TextScaled = true
	b.Font = Enum.Font.GothamBold
	b.TextColor3 = Color3.new(1, 1, 1)
	b.AutoButtonColor = true
	corner(b, 8)
	return b
end

local function panelLabel(text: string, position: UDim2, parent: Instance): TextLabel
	local l = Instance.new("TextLabel")
	l.Size = UDim2.new(1, -20, 0, 28)
	l.Position = position
	l.BackgroundTransparency = 1
	l.Text = text
	l.TextScaled = true
	l.Font = Enum.Font.GothamBold
	l.TextColor3 = Color3.new(1, 1, 1)
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.Parent = parent
	return l
end

function HUD.new()
	local self = setmetatable({}, HUD)

	local gui = Instance.new("ScreenGui")
	gui.Name = "GrowOrRotHUD"
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	self.gui = gui

	-- Coins
	local coins = Instance.new("TextLabel")
	coins.Name = "Coins"
	coins.Size = UDim2.fromOffset(220, 52)
	coins.Position = UDim2.fromOffset(16, 16)
	coins.BackgroundColor3 = Color3.fromRGB(24, 26, 30)
	coins.BackgroundTransparency = 0.15
	coins.BorderSizePixel = 0
	coins.Text = "loading..."
	coins.TextScaled = true
	coins.Font = Enum.Font.GothamBold
	coins.TextColor3 = Color3.fromRGB(255, 214, 66)
	corner(coins, 10)
	coins.Parent = gui
	self.coins = coins

	-- Weather banner
	local weather = Instance.new("TextLabel")
	weather.Name = "Weather"
	weather.Size = UDim2.fromOffset(260, 40)
	weather.Position = UDim2.new(0.5, -130, 0, 16)
	weather.BackgroundColor3 = Color3.fromRGB(30, 44, 60)
	weather.BackgroundTransparency = 0.15
	weather.BorderSizePixel = 0
	weather.Text = ""
	weather.TextScaled = true
	weather.Font = Enum.Font.GothamBold
	weather.TextColor3 = Color3.fromRGB(190, 225, 255)
	corner(weather, 10)
	weather.Parent = gui
	self.weather = weather

	-- Shop toggle + panel
	self.shopToggle = button(
		"SHOP",
		Color3.fromRGB(58, 92, 190),
		UDim2.fromOffset(120, 48),
		UDim2.new(1, -136, 0, 16)
	)
	self.shopToggle.Parent = gui

	local panel = Instance.new("Frame")
	panel.Name = "Shop"
	panel.Size = UDim2.fromOffset(320, 430)
	panel.Position = UDim2.new(1, -336, 0, 76)
	panel.BackgroundColor3 = Color3.fromRGB(24, 26, 30)
	panel.BackgroundTransparency = 0.08
	panel.BorderSizePixel = 0
	panel.Visible = false
	corner(panel, 12)
	panel.Parent = gui
	self.panel = panel

	panelLabel("Seeds", UDim2.fromOffset(10, 8), panel)
	self.buySwift = button(
		"Swift Seed — 50",
		Color3.fromRGB(46, 120, 60),
		UDim2.new(1, -20, 0, 40),
		UDim2.fromOffset(10, 40)
	)
	self.buySwift.Parent = panel
	self.buyVolatile = button(
		"Volatile Seed — 250",
		Color3.fromRGB(46, 120, 60),
		UDim2.new(1, -20, 0, 40),
		UDim2.fromOffset(10, 86)
	)
	self.buyVolatile.Parent = panel

	panelLabel("Passes", UDim2.fromOffset(10, 136), panel)
	self.passRotInsurance = button(
		"Rot Insurance",
		Color3.fromRGB(150, 80, 60),
		UDim2.new(1, -20, 0, 40),
		UDim2.fromOffset(10, 168)
	)
	self.passRotInsurance.Parent = panel
	self.passSeedLuck = button(
		"Seed Luck",
		Color3.fromRGB(150, 80, 60),
		UDim2.new(1, -20, 0, 40),
		UDim2.fromOffset(10, 214)
	)
	self.passSeedLuck.Parent = panel
	self.passAutoHarvest = button(
		"Auto Harvest",
		Color3.fromRGB(150, 80, 60),
		UDim2.new(1, -20, 0, 40),
		UDim2.fromOffset(10, 260)
	)
	self.passAutoHarvest.Parent = panel

	panelLabel("Boosts", UDim2.fromOffset(10, 310), panel)
	self.buyPlot = button(
		"Extra Plot",
		Color3.fromRGB(58, 92, 190),
		UDim2.new(1, -20, 0, 40),
		UDim2.fromOffset(10, 342)
	)
	self.buyPlot.Parent = panel
	self.buyInstantGrow = button(
		"Instant Grow",
		Color3.fromRGB(58, 92, 190),
		UDim2.new(1, -20, 0, 40),
		UDim2.fromOffset(10, 388)
	)
	self.buyInstantGrow.Parent = panel

	self.shopToggle.Activated:Connect(function()
		panel.Visible = not panel.Visible
	end)

	-- Toast column for push-tick outcomes
	local toasts = Instance.new("Frame")
	toasts.Name = "Toasts"
	toasts.Size = UDim2.fromOffset(320, 220)
	toasts.Position = UDim2.new(0, 16, 1, -240)
	toasts.BackgroundTransparency = 1
	toasts.Parent = gui

	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.VerticalAlignment = Enum.VerticalAlignment.Bottom
	layout.Padding = UDim.new(0, 4)
	layout.Parent = toasts
	self.toasts = toasts
	self.toastCounter = 0

	return self
end

--[[
	Feedback for a resolved push tick.

	This exists because a state diff is not readable as an event. "You had 340
	coins of Prismatic and now you have an empty plot" needs to land as a moment,
	not as a number quietly changing.
]]
function HUD:toast(text: string, color: Color3)
	self.toastCounter += 1

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 0, 34)
	label.BackgroundColor3 = Color3.fromRGB(20, 22, 26)
	label.BackgroundTransparency = 0.2
	label.BorderSizePixel = 0
	label.Text = text
	label.TextScaled = true
	label.Font = Enum.Font.GothamBold
	label.TextColor3 = color
	label.LayoutOrder = self.toastCounter
	corner(label, 6)
	label.Parent = self.toasts

	task.delay(4, function()
		if label.Parent then
			label:Destroy()
		end
	end)
end

function HUD:renderWeather(weather)
	if not weather then
		self.weather.Text = ""
		return
	end
	local remaining = math.max(0, weather.endsAt - os.time())
	self.weather.Text = string.format("%s  ·  %ds", weather.displayName, remaining)
end

function HUD:render(state)
	if not state then
		self.coins.Text = "loading..."
		return
	end

	self.coins.Text = string.format("%d coins", state.coins)
	self.lastWeather = state.weather
	self:renderWeather(state.weather)

	local swift = state.seeds and state.seeds.swift or 0
	local volatileHeld = state.seeds and state.seeds.volatile or 0
	self.buySwift.Text = string.format("Swift Seed — 50  (x%d)", swift)
	self.buyVolatile.Text = string.format("Volatile Seed — 250  (x%d)", volatileHeld)

	-- Owned passes stop being purchase prompts and become status.
	local passes = state.passes or {}
	self.passRotInsurance.Text = passes.rotInsurance and "Rot Insurance ✓" or "Rot Insurance"
	self.passSeedLuck.Text = passes.seedLuck and "Seed Luck ✓" or "Seed Luck"
	self.passAutoHarvest.Text = passes.autoHarvest and "Auto Harvest ✓" or "Auto Harvest"
end

return HUD
