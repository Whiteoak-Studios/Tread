--[[
    The dev place's live-run panel, shown on its key or a touch screen's
    button: a button for each live run and Run all, one for each report the
    queue kept, the status, and the report in a box that selects whole
--]]

--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextService = game:GetService("TextService")
local UserInputService = game:GetService("UserInputService")
local Player = Players.LocalPlayer

local Network = require(ReplicatedStorage.Shared.Network.Client)

local LiveRuns = require(ReplicatedStorage.Shared.Dev.LiveRuns)

local LiveConfig = require(script.Parent.Config).live

local KEY: Enum.KeyCode = LiveConfig.key
local WAIT: number = LiveConfig.wait
local SIZE: Vector2 = LiveConfig.size
local LIST: number = LiveConfig.list
local ROW: number = LiveConfig.row
local GAP: number = LiveConfig.gap
local BAR: number = LiveConfig.bar
local TEXT_SIZE: number = LiveConfig.textSize
local FONT: Enum.Font = Enum.Font.Code -- Every character the same width, so the report's columns line up
local UNBOUNDED: number = math.huge -- The report is measured with no limit on its height
local FRAME_LAYER: number = 1 -- The panel's frame, under its parts
local PART_LAYER: number = 2 -- The status line, the run buttons' column and the report's frame
local CONTENT_LAYER: number = 3 -- The buttons and the report's box, over the frames they sit in
local BUTTON_ORDER: number = 1 -- The touch button's screen, drawn over the panel's wherever the two meet
local ALL_ORDER: number = 0 -- Run all's place in the column, above every run
local KEPT_COLOR: Color3 = Color3.fromRGB(40, 70, 40) -- A kept report's button, apart from the runs'
local LINES: string = "[^\n]+" -- Each line of the kept list
local SEPARATOR: string = " | " -- Between the queue's status line and the panel's own

-- The panel's parts its listeners bring up to date
type Gui = {
	screen: ScreenGui,
	status: TextLabel,
	column: ScrollingFrame,
	report: ScrollingFrame,
	box: TextBox,
	buttons: { [TextButton]: string }, -- Each button's run, Run all's among them
	kept: { TextButton }, -- One for each report the queue kept, in its order
}

local Screen: ScreenGui? = nil -- The panel, once the PlayerGui it waits for has come
local Started: boolean = false

local Live = {}

-- One of the column's buttons, at its place in the column's order
local function columnButton(column: ScrollingFrame, text: string, order: number): TextButton
	local made: TextButton = Instance.new("TextButton")
	made.Name = text
	made.Text = text
	made.LayoutOrder = order
	made.Size = UDim2.fromOffset(LIST - BAR, ROW)
	made.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
	made.TextColor3 = Color3.new(1, 1, 1)
	made.TextSize = TEXT_SIZE
	made.ZIndex = CONTENT_LAYER
	made.Parent = column

	return made
end

--[[
    The panel, hidden, centered on the screen: the status line across its
    top, a column of Run all and a button for each run beside the report's
    frame, and in the frame the box the report shows in, editable so it
    takes focus
--]]

local function build(playerGui: PlayerGui): Gui
	local top: number = ROW + 2 * GAP -- Pixels from the panel's top to the column and the report, under the status
	local body: number = SIZE.Y - top - GAP -- Pixels down the column and the report
	local reportWidth: number = SIZE.X - LIST - 3 * GAP

	local screen: ScreenGui = Instance.new("ScreenGui")
	screen.Name = "DevLive"
	screen.ResetOnSpawn = false
	screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screen.Enabled = false
	screen.Parent = playerGui

	local frame: Frame = Instance.new("Frame")
	frame.Name = "Panel"
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.fromScale(0.5, 0.5)
	frame.Size = UDim2.fromOffset(SIZE.X, SIZE.Y)
	frame.BackgroundColor3 = Color3.new(0, 0, 0)
	frame.BackgroundTransparency = 0.25
	frame.ZIndex = FRAME_LAYER
	frame.Parent = screen

	local status: TextLabel = Instance.new("TextLabel")
	status.Name = "Status"
	status.Position = UDim2.fromOffset(GAP, GAP)
	status.Size = UDim2.fromOffset(SIZE.X - 2 * GAP, ROW)
	status.BackgroundTransparency = 1
	status.TextColor3 = Color3.new(1, 1, 1)
	status.TextSize = TEXT_SIZE
	status.TextXAlignment = Enum.TextXAlignment.Left
	status.ZIndex = PART_LAYER
	status.Parent = frame

	local column: ScrollingFrame = Instance.new("ScrollingFrame")
	column.Name = "Runs"
	column.Position = UDim2.fromOffset(GAP, top)
	column.Size = UDim2.fromOffset(LIST, body)
	column.CanvasSize = UDim2.fromOffset(0, (#LiveRuns.runs + 1) * (ROW + GAP))
	column.ScrollBarThickness = BAR
	column.BackgroundTransparency = 1
	column.ZIndex = PART_LAYER
	column.Parent = frame

	local layout: UIListLayout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, GAP)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = column

	local buttons: { [TextButton]: string } = {}
	local all: TextButton = columnButton(column, LiveRuns.ALL, ALL_ORDER)
	buttons[all] = LiveRuns.ALL

	for index: number, run: LiveRuns.Run in LiveRuns.runs do
		buttons[columnButton(column, run.name, index)] = run.name
	end

	local report: ScrollingFrame = Instance.new("ScrollingFrame")
	report.Name = "Report"
	report.Position = UDim2.fromOffset(LIST + 2 * GAP, top)
	report.Size = UDim2.fromOffset(reportWidth, body)
	report.CanvasSize = UDim2.fromOffset(0, body)
	report.ScrollBarThickness = BAR
	report.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
	report.ZIndex = PART_LAYER
	report.Parent = frame

	local box: TextBox = Instance.new("TextBox")
	box.Name = "Text"
	box.Text = ""
	box.TextEditable = true -- A box that isn't editable may never take focus, so the panel puts back any edit instead
	box.ClearTextOnFocus = false
	box.MultiLine = true
	box.TextWrapped = true
	box.RichText = false
	box.Font = FONT
	box.TextSize = TEXT_SIZE
	box.TextXAlignment = Enum.TextXAlignment.Left
	box.TextYAlignment = Enum.TextYAlignment.Top
	box.TextColor3 = Color3.new(1, 1, 1)
	box.BackgroundTransparency = 1
	box.Size = UDim2.fromOffset(reportWidth - BAR, body)
	box.ZIndex = CONTENT_LAYER
	box.Parent = report

	return {
		screen = screen,
		status = status,
		column = column,
		report = report,
		box = box,
		buttons = buttons,
		kept = {},
	}
end

--[[
    The button a touch screen with no keyboard shows and hides the panel
    by, always on screen in a screen of its own at the top edge's middle,
    clear of the dev game's stick, look drag and jump button
--]]

local function touchButton(playerGui: PlayerGui): TextButton
	local screen: ScreenGui = Instance.new("ScreenGui")
	screen.Name = "DevLiveButton"
	screen.ResetOnSpawn = false
	screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screen.DisplayOrder = BUTTON_ORDER
	screen.Parent = playerGui

	local button: TextButton = Instance.new("TextButton")
	button.Name = "Toggle"
	button.Text = "Live"
	button.AnchorPoint = Vector2.new(0.5, 0)
	button.Position = UDim2.new(0.5, 0, 0, 8)
	button.Size = UDim2.fromOffset(96, 40)
	button.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
	button.BackgroundTransparency = 0.25
	button.TextColor3 = Color3.new(1, 1, 1)
	button.TextSize = TEXT_SIZE
	button.ZIndex = CONTENT_LAYER
	button.Parent = screen

	return button
end

--[[
    Brings the panel up to what it shows. The box is sized from its text's
    measured height and the canvas from the box, since an automatic size
    never grows a child past the frame it sits in
--]]

local function show(gui: Gui, panel: LiveRuns.Panel)
	gui.status.Text = panel.queue ~= "" and `{panel.queue}{SEPARATOR}{panel.status}` or panel.status
	gui.box.Text = panel.text

	local width: number = gui.box.Size.X.Offset
	local measured: Vector2 = TextService:GetTextSize(panel.text, TEXT_SIZE, FONT, Vector2.new(width, UNBOUNDED))

	-- At least the frame's height, so a click anywhere in the frame reaches the box
	local height: number = math.max(measured.Y, gui.report.Size.Y.Offset)
	gui.box.Size = UDim2.fromOffset(width, height)
	gui.report.CanvasSize = UDim2.fromOffset(0, height)
end

--[[
    Lists the reports the queue kept, a button each under the runs, which
    asks the server for that report, in place of the ones listed before,
    whose connections go with them
--]]

local function list(gui: Gui, text: string)
	for _, old: TextButton in gui.kept do
		old:Destroy()
	end

	table.clear(gui.kept)

	for line: string in string.gmatch(text, LINES) do
		local index: number = #gui.kept + 1
		local kept: TextButton = columnButton(gui.column, line, #LiveRuns.runs + index)
		kept.BackgroundColor3 = KEPT_COLOR
		kept.TextScaled = true -- A long line shrinks to its button rather than losing its verdict
		kept.Activated:Connect(function ()
			Network.run.fire(LiveRuns.kept(index))
		end)

		table.insert(gui.kept, kept)
	end

	local rows: number = #LiveRuns.runs + 1 + #gui.kept
	gui.column.CanvasSize = UDim2.fromOffset(0, rows * (ROW + GAP))
end

--[[
    Builds the panel, hidden, and connects its key, its buttons, its box's
    selection and edits, and the server's reports, each for the client
    session, with a button for the key on a touch screen with no keyboard.
    It runs once a client, and waits at boot for the PlayerGui
--]]

function Live.start()
	if Started then
		error("Live.start runs once a client, and it has already run", 2)
	end

	Started = true

	-- Boot-time wait: the PlayerGui may not have arrived when the client's scripts start
	local playerGui = Player:WaitForChild("PlayerGui", WAIT) :: PlayerGui?
	if not playerGui then
		error(`The live panel found no PlayerGui within {WAIT} s`)
	end

	local gui: Gui = build(playerGui)
	local panel: LiveRuns.Panel = LiveRuns.idle()
	Screen = gui.screen
	show(gui, panel)

	Network.runReport.on(function (state: LiveRuns.State, text: string)
		if state == "Kept" then
			list(gui, text)
		end

		panel = LiveRuns.apply(panel, state, text)
		show(gui, panel)
	end)

	for run: TextButton, name: string in gui.buttons do
		run.Activated:Connect(function ()
			Network.run.fire(name)
		end)
	end

	-- The queue's state and its kept list, should a queue have run on this server before the client joined
	Network.run.fire(LiveRuns.kept(0))

	-- The whole report is selected as the box takes focus, so a copy takes all of it. Deferred, since the engine places
	-- its own cursor for the click that focused the box after Focused fires
	local function selectAll()
		gui.box.CursorPosition = #gui.box.Text + 1
		gui.box.SelectionStart = 1
	end

	gui.box.Focused:Connect(function ()
		task.defer(selectAll)
	end)

	-- Any edit to the box puts the report back. Comparing with the report, rather than flagging the panel's own
	-- writes, holds whether the signal fires at the write or deferred, and the put-back's own signal finds them equal
	gui.box:GetPropertyChangedSignal("Text"):Connect(function ()
		if gui.box.Text ~= panel.text then
			gui.box.Text = panel.text
		end
	end)

	-- Shows the panel or hides it, on its key and on a touch screen's button alike
	local function toggle()
		gui.screen.Enabled = not gui.screen.Enabled
	end

	-- A key typed into the focused box is processed, so L there neither toggles the panel nor stays in the report
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

-- Whether the panel shows, which the dev client frees the mouse for
function Live.open(): boolean
	local screen: ScreenGui? = Screen
	if screen then
		return screen.Enabled
	end

	return false
end

return Live
