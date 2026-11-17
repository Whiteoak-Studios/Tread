--[[
    The arm's panel, shown on its key and by itself once the program ends: the
    run's status, and the server's report then this client's in a box that
    selects whole, so a live server's report can be copied
--]]

--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TextService = game:GetService("TextService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local Player = Players.LocalPlayer

local Config = require(ReplicatedStorage.Arm.Config)

local RUN_ATTRIBUTE: string = Config.runAttribute
local DONE_ATTRIBUTE: string = Config.doneAttribute
local REPORT_NAME: string = Config.reportName
local KEY: Enum.KeyCode = Config.panel.key
local WAIT: number = Config.panel.wait
local SIZE: Vector2 = Config.panel.size
local ROW: number = Config.panel.row
local GAP: number = Config.panel.gap
local BAR: number = Config.panel.bar
local TEXT_SIZE: number = Config.panel.textSize
local FONT: Enum.Font = Enum.Font.Code -- Every character the same width, so the report's columns line up
local UNBOUNDED: number = math.huge -- The report is measured with no limit on its height
local FREE_MOUSE: string = "ArmPanelMouse" -- The render step that frees the mouse while the panel shows
local AFTER_CAMERA: number = Enum.RenderPriority.Camera.Value + 1 -- After the default camera locks the mouse each frame
local FRAME_LAYER: number = 1 -- The panel's frame, under its parts
local PART_LAYER: number = 2 -- The status line and the report's frame
local CONTENT_LAYER: number = 3 -- The report's box, over the frame it sits in
local NEWLINE: string = "\n" -- Between the server's lines and this client's

-- The panel's parts its listeners bring up to date
type Gui = {
	screen: ScreenGui,
	status: TextLabel,
	report: ScrollingFrame,
	box: TextBox,
}

local Panel = {}

--[[
    The panel, hidden, centered on the screen: the status line across its
    top and the report's frame under it, and in the frame the box the report
    shows in, editable so it takes focus
--]]

local function build(playerGui: PlayerGui): Gui
	local top: number = ROW + 2 * GAP -- Pixels from the panel's top to the report, under the status
	local body: number = SIZE.Y - top - GAP -- Pixels down the report
	local width: number = SIZE.X - 2 * GAP

	local screen: ScreenGui = Instance.new("ScreenGui")
	screen.Name = "ArmPanel"
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
	status.Size = UDim2.fromOffset(width, ROW)
	status.BackgroundTransparency = 1
	status.TextColor3 = Color3.new(1, 1, 1)
	status.TextSize = TEXT_SIZE
	status.TextXAlignment = Enum.TextXAlignment.Left
	status.ZIndex = PART_LAYER
	status.Parent = frame

	local report: ScrollingFrame = Instance.new("ScrollingFrame")
	report.Name = "Report"
	report.Position = UDim2.fromOffset(GAP, top)
	report.Size = UDim2.fromOffset(width, body)
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
	box.Size = UDim2.fromOffset(width - BAR, body)
	box.ZIndex = CONTENT_LAYER
	box.Parent = report

	return {
		screen = screen,
		status = status,
		report = report,
		box = box,
	}
end

--[[
    The program done, the run going, or a wait for the next run, from the
    attributes the server sets on Workspace
--]]

local function status(): string
	if Workspace:GetAttribute(DONE_ATTRIBUTE) == true then
		return "Done: every run has finished. Click the report to select it all, then copy it"
	end

	local label: any = Workspace:GetAttribute(RUN_ATTRIBUTE)
	if type(label) == "string" then
		return `Running {label}`
	end

	return "Waiting for the next run"
end

--[[
    Brings the panel up to the status and the report. The box is sized from
    its text's measured height and the canvas from the box, since an
    automatic size never grows a child past the frame it sits in
--]]

local function show(gui: Gui, text: string)
	gui.status.Text = status()
	gui.box.Text = text

	local width: number = gui.box.Size.X.Offset
	local measured: Vector2 = TextService:GetTextSize(text, TEXT_SIZE, FONT, Vector2.new(width, UNBOUNDED))

	-- At least the frame's height, so a click anywhere in the frame reaches the box
	local height: number = math.max(measured.Y, gui.report.Size.Y.Offset)
	gui.box.Size = UDim2.fromOffset(width, height)
	gui.report.CanvasSize = UDim2.fromOffset(0, height)
end

--[[
    Shows the panel or hides it. While it shows, a render step after the
    default camera's frees the mouse each frame, so the report can be
    clicked in first person too, and hiding the panel unbinds it
--]]

local function setOpen(gui: Gui, open: boolean)
	if gui.screen.Enabled == open then
		return
	end

	gui.screen.Enabled = open

	if not open then
		RunService:UnbindFromRenderStep(FREE_MOUSE)
		return
	end

	RunService:BindToRenderStep(FREE_MOUSE, AFTER_CAMERA, function ()
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	end)
end

--[[
    Builds the panel, hidden, and connects its key, its box's selection and
    edits, the server's attributes and both reports, each for the client
    session. It waits at boot for the PlayerGui and the server's report, and
    takes this client's report from the client that made it
--]]

function Panel.start(clientReport: StringValue)
	-- Boot-time waits: neither may have arrived when the client's scripts start
	local playerGui = Player:WaitForChild("PlayerGui", WAIT) :: PlayerGui?
	if not playerGui then
		error(`The arm's panel found no PlayerGui within {WAIT} s`)
	end

	local serverReport = ReplicatedStorage:WaitForChild(REPORT_NAME, WAIT) :: StringValue?
	if not serverReport then
		error(`The arm's panel found no ReplicatedStorage.{REPORT_NAME} within {WAIT} s`)
	end

	local gui: Gui = build(playerGui)
	local text: string = "" -- The report the box shows, which any edit is put back to

	local function refresh()
		local server: string = serverReport.Value
		local client: string = clientReport.Value
		text = server ~= "" and client ~= "" and `{server}{NEWLINE}{client}` or `{server}{client}`
		show(gui, text)
	end

	-- The program's end opens the panel on the report, on a client that joined after it too
	local function ended()
		refresh()

		if Workspace:GetAttribute(DONE_ATTRIBUTE) == true then
			setOpen(gui, true)
		end
	end

	-- Each of these lives for the client session, as the panel does, so none keeps a disconnect
	serverReport:GetPropertyChangedSignal("Value"):Connect(refresh)
	clientReport:GetPropertyChangedSignal("Value"):Connect(refresh)
	Workspace:GetAttributeChangedSignal(RUN_ATTRIBUTE):Connect(refresh)
	Workspace:GetAttributeChangedSignal(DONE_ATTRIBUTE):Connect(ended)

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
		if gui.box.Text ~= text then
			gui.box.Text = text
		end
	end)

	-- A key typed into the focused box or the chat is processed, so L there neither toggles the panel nor stays in the
	-- report
	UserInputService.InputBegan:Connect(function (input: InputObject, processed: boolean)
		if not processed and input.KeyCode == KEY then
			setOpen(gui, not gui.screen.Enabled)
		end
	end)

	ended()
end

return Panel
