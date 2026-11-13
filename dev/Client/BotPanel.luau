--[[
    The dev place's bot panel, shown on its key or a touch screen's button:
    a spawn of bots by count, behavior and area, a clear of them, and the
    server's frame and tick-stage numbers each second it shows
--]]

--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Player = Players.LocalPlayer

local Network = require(ReplicatedStorage.Shared.Network.Client)

local PanelConfig = require(script.Parent.Config).botPanel
local LiveConfig = require(script.Parent.Config).live -- The live panel's look, which this one shares

local KEY: Enum.KeyCode = PanelConfig.key
local WAIT: number = PanelConfig.wait
local WIDTH: number = PanelConfig.width
local MARGIN: number = PanelConfig.margin
local COUNT: number = PanelConfig.count
local RADII: { number } = PanelConfig.radii
local ROW: number = LiveConfig.row
local GAP: number = LiveConfig.gap
local TEXT_SIZE: number = LiveConfig.textSize
local COUNT_MOST: number = 2 ^ 16 - 1 -- The most the botSpawn event's u16 count carries
local FONT: Enum.Font = Enum.Font.Code -- Every character the same width, so the numbers' columns line up
local FRAME_LAYER: number = 1 -- The panel's frame, under its parts
local PART_LAYER: number = 2 -- The lines and the rows' frames
local CONTENT_LAYER: number = 3 -- The buttons and the count's box, over the rows they sit in
local BUTTON_ORDER: number = 1 -- The touch button's screen, drawn over the panel's wherever the two meet

-- How a spawn's bots move, as the botSpawn event names them, in the order the behavior button cycles through them
local BEHAVIORS: { Behavior } = { "Idle", "Walk", "Sprint" }

type Behavior = "Idle" | "Walk" | "Sprint"

-- The panel's parts its listeners bring up to date
type Gui = {
	screen: ScreenGui,
	status: TextLabel,
	refusal: TextLabel,
	count: TextBox,
	behavior: TextButton,
	area: TextButton,
	spawn: TextButton,
	clear: TextButton,
	numbers: TextLabel,
}

local Screen: ScreenGui? = nil -- The panel, once the PlayerGui it waits for has come
local Started: boolean = false

local BotPanel = {}

-- A line of text across the panel, a row tall and taller as its wrapped text needs
local function line(name: string, order: number, parent: Instance): TextLabel
	local label: TextLabel = Instance.new("TextLabel")
	label.Name = name
	label.LayoutOrder = order
	label.Size = UDim2.new(1, 0, 0, ROW)
	label.AutomaticSize = Enum.AutomaticSize.Y
	label.BackgroundTransparency = 1
	label.TextColor3 = Color3.new(1, 1, 1)
	label.Font = FONT
	label.TextSize = TEXT_SIZE
	label.TextWrapped = true
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Top
	label.ZIndex = PART_LAYER
	label.Parent = parent

	return label
end

-- A button of the panel's, named for what it does
local function button(name: string, order: number, size: UDim2, parent: Instance): TextButton
	local made: TextButton = Instance.new("TextButton")
	made.Name = name
	made.Text = name
	made.LayoutOrder = order
	made.Size = size
	made.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
	made.TextColor3 = Color3.new(1, 1, 1)
	made.TextSize = TEXT_SIZE
	made.ZIndex = CONTENT_LAYER
	made.Parent = parent

	return made
end

-- A row of the panel's a row tall, whose two parts the caller puts in it side by side
local function row(name: string, order: number, parent: Instance): Frame
	local frame: Frame = Instance.new("Frame")
	frame.Name = name
	frame.LayoutOrder = order
	frame.Size = UDim2.new(1, 0, 0, ROW)
	frame.BackgroundTransparency = 1
	frame.ZIndex = PART_LAYER
	frame.Parent = parent

	return frame
end

--[[
    The panel, hidden, at the screen's left edge, clear of the live panel
    in its middle: a line each for the panel's bots and the last refusal,
    the count, the behavior and the area, Spawn beside Clear, then the
    server's numbers, its height whatever its lines need
--]]

local function build(playerGui: PlayerGui): Gui
	local half: UDim2 = UDim2.new(0.5, -GAP / 2, 1, 0) -- Each of a row's two parts
	local across: UDim2 = UDim2.new(1, 0, 0, ROW) -- A button the panel's width

	local screen: ScreenGui = Instance.new("ScreenGui")
	screen.Name = "DevBots"
	screen.ResetOnSpawn = false
	screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screen.Enabled = false
	screen.Parent = playerGui

	local frame: Frame = Instance.new("Frame")
	frame.Name = "Panel"
	frame.AnchorPoint = Vector2.new(0, 0.5)
	frame.Position = UDim2.new(0, MARGIN, 0.5, 0)
	frame.Size = UDim2.fromOffset(WIDTH, 0)
	frame.AutomaticSize = Enum.AutomaticSize.Y
	frame.BackgroundColor3 = Color3.new(0, 0, 0)
	frame.BackgroundTransparency = 0.25
	frame.ZIndex = FRAME_LAYER
	frame.Parent = screen

	local padding: UIPadding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, GAP)
	padding.PaddingBottom = UDim.new(0, GAP)
	padding.PaddingLeft = UDim.new(0, GAP)
	padding.PaddingRight = UDim.new(0, GAP)
	padding.Parent = frame

	local layout: UIListLayout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, GAP)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = frame

	local status: TextLabel = line("Status", 1, frame)
	status.Text = "Panel bots: waiting for the server"

	local refusal: TextLabel = line("Refusal", 2, frame)
	refusal.Text = "Last refusal: none"

	local countRow: Frame = row("CountRow", 3, frame)
	local countLabel: TextLabel = line("CountLabel", 1, countRow)
	countLabel.Text = "Count"
	countLabel.Size = half
	countLabel.TextYAlignment = Enum.TextYAlignment.Center

	local count: TextBox = Instance.new("TextBox")
	count.Name = "Count"
	count.Text = `{COUNT}`
	count.ClearTextOnFocus = false
	count.Position = UDim2.fromScale(0.5, 0)
	count.Size = half
	count.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
	count.TextColor3 = Color3.new(1, 1, 1)
	count.Font = FONT
	count.TextSize = TEXT_SIZE
	count.ZIndex = CONTENT_LAYER
	count.Parent = countRow

	local behavior: TextButton = button("Behavior", 4, across, frame)
	local area: TextButton = button("Area", 5, across, frame)

	local actions: Frame = row("Actions", 6, frame)
	local spawn: TextButton = button("Spawn", 1, half, actions)
	local clear: TextButton = button("Clear", 2, half, actions)
	clear.Position = UDim2.fromScale(0.5, 0)

	local numbers: TextLabel = line("Numbers", 7, frame)
	numbers.Text = ""

	return {
		screen = screen,
		status = status,
		refusal = refusal,
		count = count,
		behavior = behavior,
		area = area,
		spawn = spawn,
		clear = clear,
		numbers = numbers,
	}
end

--[[
    The button a touch screen with no keyboard shows and hides the panel
    by, always on screen in a screen of its own at the top edge, left of
    the live panel's own button there
--]]

local function touchButton(playerGui: PlayerGui): TextButton
	local screen: ScreenGui = Instance.new("ScreenGui")
	screen.Name = "DevBotsButton"
	screen.ResetOnSpawn = false
	screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screen.DisplayOrder = BUTTON_ORDER
	screen.Parent = playerGui

	-- The live panel's button spans 48 pixels either side of the top edge's middle, so this one ends 8 short of it
	local toggle: TextButton = button("Toggle", 1, UDim2.fromOffset(96, 40), screen)
	toggle.Text = "Bots"
	toggle.AnchorPoint = Vector2.new(1, 0)
	toggle.Position = UDim2.new(0.5, -56, 0, 8)
	toggle.BackgroundTransparency = 0.25

	return toggle
end

-- What the area button shows for the area at that place in its cycle, the whole map past the radii
local function areaText(place: number): string
	local radius: number? = RADII[place]
	if radius then
		return `Area: {radius} studs either way of me`
	end

	return "Area: the whole map"
end

--[[
    Builds the panel, hidden, and connects its key, its buttons and the
    server's numbers and refusals, each for the client session, with a
    button for the key on a touch screen with no keyboard. It runs once a
    client, and waits at boot for the PlayerGui when it has not come yet
--]]

function BotPanel.start()
	if Started then
		error("BotPanel.start runs once a client, and it has already run", 2)
	end

	Started = true

	local playerGui: PlayerGui? = Player:FindFirstChildOfClass("PlayerGui")
	if not playerGui then
		-- Boot-time wait: the PlayerGui may not have arrived when the client's scripts start
		playerGui = Player:WaitForChild("PlayerGui", WAIT) :: PlayerGui?
	end

	if not playerGui then
		error(`The bot panel found no PlayerGui within {WAIT} s`)
	end

	local gui: Gui = build(playerGui)
	local behavior: number = 1 -- The behavior's place in BEHAVIORS
	local area: number = 1 -- The area's place in RADII, one past it the whole map
	Screen = gui.screen
	gui.behavior.Text = `Behavior: {BEHAVIORS[behavior]}`
	gui.area.Text = areaText(area)

	Network.botStats.on(function (made: number, text: string)
		gui.status.Text = `Panel bots: {made} on the server`
		gui.numbers.Text = text
	end)

	Network.botRefused.on(function (reason: string)
		gui.refusal.Text = `Last refusal: {reason}`
	end)

	gui.behavior.Activated:Connect(function ()
		behavior = behavior % #BEHAVIORS + 1
		gui.behavior.Text = `Behavior: {BEHAVIORS[behavior]}`
	end)

	gui.area.Activated:Connect(function ()
		area = area % (#RADII + 1) + 1
		gui.area.Text = areaText(area)
	end)

	-- A count the event can't carry is refused here, and the server refuses one past its cap
	gui.spawn.Activated:Connect(function ()
		local typed: string = gui.count.Text
		local count: number? = tonumber(typed)
		if not count or count % 1 ~= 0 or count < 1 or count > COUNT_MOST then
			gui.refusal.Text = `Last refusal: the count {typed} is no whole number from 1 to {COUNT_MOST}`
			return
		end

		local radius: number? = RADII[area] -- nil one past the radii, for the whole map
		Network.botSpawn.fire(count, BEHAVIORS[behavior], radius)
	end)

	gui.clear.Activated:Connect(function ()
		Network.botClear.fire()
	end)

	-- Shows the panel or hides it, on its key and on a touch screen's button alike, and tells the server which
	local function toggle()
		gui.screen.Enabled = not gui.screen.Enabled
		Network.botWatch.fire(gui.screen.Enabled)
	end

	-- A key typed into the count's focused box is processed, so B there goes into the count and toggles nothing
	UserInputService.InputBegan:Connect(function (input: InputObject, processed: boolean)
		if not processed and input.KeyCode == KEY then
			toggle()
		end
	end)

	-- A touch screen with no keyboard has no key to press, so the button stands in for it. Its connection lives for the
	-- client session, as the panel's others do, and goes with the button
	if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
		touchButton(playerGui).Activated:Connect(toggle)
	end
end

-- Whether the panel shows, which the dev client frees the mouse and holds the look for
function BotPanel.open(): boolean
	local screen: ScreenGui? = Screen
	if screen then
		return screen.Enabled
	end

	return false
end

return BotPanel
