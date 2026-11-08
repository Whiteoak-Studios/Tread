--[[
    The dev place's client: starts Tread's client as a game does, with the
    dev game's shared table and Frontier Zero's client settings, then the
    exploit kit, the test elevator, input, camera, mantle prompt and G2 counts
--]]

--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local packages = ReplicatedStorage.Packages
local Player = Players.LocalPlayer

local Tread = require(packages.Tread)

local Network = require(ReplicatedStorage.Shared.Network.Client)

local Config = require(script.Config)
local Elevator = require(ReplicatedStorage.Shared.Dev.Elevator)
local Exploits = require(script.Exploits)
local Input = require(script.Input)
local Rig = require(script.Rig)
local View = require(script.View)
local Shared = require(ReplicatedStorage.Shared.Dev.Config)

local Camera = Workspace.CurrentCamera

local VIEW_KEY: Enum.KeyCode = Enum.KeyCode.V -- The dev place's own bind, which no game shares
local PRESS_KEY: Enum.KeyCode = Config.elevator.key
local PROMPT_WAIT: number = Config.prompt.wait

local input = Input.new()

-- The shoulder view's cast meets the same parts the dev game's collision does
local include: { Instance }? = Shared.collision.include
if not include then
	error("The dev game's collision names no parts for the shoulder view's cast to meet")
end

local castParams: RaycastParams = RaycastParams.new()
castParams.FilterType = Enum.RaycastFilterType.Include
castParams.FilterDescendantsInstances = include

-- How far the view's sphere gets from the eye toward the shoulder view before it meets the world, nil for all the way
local function cast(origin: Vector3, direction: Vector3): number?
	local hit: RaycastResult? = Workspace:Spherecast(origin, Config.view.radius, direction, castParams)
	if hit then
		return hit.Distance
	end

	return nil
end

--[[
    The mantle prompt, a label made in code below the middle of the screen
    and hidden until a jump press would start a mantle. It waits at boot
    for the PlayerGui
--]]

local function prompt(): TextLabel
	-- Boot-time wait: the PlayerGui may not have arrived when the client's scripts start
	local playerGui = Player:WaitForChild("PlayerGui", PROMPT_WAIT) :: PlayerGui?
	if not playerGui then
		error(`The mantle prompt found no PlayerGui within {PROMPT_WAIT} s`)
	end

	local screen: ScreenGui = Instance.new("ScreenGui")
	screen.Name = "DevPrompt"
	screen.ResetOnSpawn = false
	screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screen.Parent = playerGui

	local label: TextLabel = Instance.new("TextLabel")
	label.Name = "Mantle"
	label.Text = Config.prompt.text
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromScale(0.5, 0.62)
	label.Size = UDim2.fromOffset(180, 32)
	label.BackgroundColor3 = Color3.new(0, 0, 0)
	label.BackgroundTransparency = 0.4
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextSize = 18
	label.ZIndex = 1
	label.Visible = false
	label.Parent = screen

	return label
end

--[[
    Builds the test elevator's car and call button from the numbers the
    server checks a press by, outside the test content so none of Tread's
    casts meets them, and registers the car with Tread, which moves its
    pivot, the platform's origin, every frame. Gives back the button
--]]

local function elevator(tread: Tread.Client): Part
	local folder: Folder = Instance.new("Folder")
	folder.Name = "Elevator"

	local platform: Tread.Platform = Elevator.platform
	local origin: Vector3 = platform.path(0, nil) -- Where it rests before any call
	local car: Model = Instance.new("Model")
	car.Name = "Car"

	for _, box: { center: Vector3, size: Vector3 } in platform.boxes do
		local deck: Part = Instance.new("Part")
		deck.Name = "Deck"
		deck.Anchored = true
		deck.CanCollide = false
		deck.CanQuery = false
		deck.CanTouch = false
		deck.Size = box.size
		deck.CFrame = CFrame.new(origin + box.center)
		deck.Color = Color3.fromRGB(90, 140, 200)
		deck.Parent = car
	end

	car.WorldPivot = CFrame.new(origin)
	car.Parent = folder

	-- Queried, since the press's ray meets it, but it neither collides nor is touched
	local button: Part = Instance.new("Part")
	button.Name = "Button"
	button.Anchored = true
	button.CanCollide = false
	button.CanQuery = true
	button.CanTouch = false
	button.Size = Elevator.buttonSize
	button.CFrame = Elevator.button
	button.Color = Color3.fromRGB(220, 50, 50)
	button.Parent = folder

	folder.Parent = Workspace

	-- Registered for the client session
	platform.model = car
	tread:addPlatform(platform)

	return button
end

local clientSettings: Tread.ClientSettings = {
	sample = function (command: Tread.Command)
		input:sample(command)
	end,

	look = function (): (number, number, number, number)
		return input:look()
	end,

	rig = Rig.template(),
	joints = Rig.joints,
	animations = Rig.animations(),
	dress = Rig.dress,
	undress = Rig.undress,
	hold = Rig.hold,
	interpolation = Config.interpolation,
	bodies = Config.bodies,
	smoothing = Config.smoothing,
	drawDistance = Config.drawDistance,
	lod = Config.lod,
	spectate = Config.spectate,
}

local client: Tread.Client = Tread.startClient(Shared, clientSettings)
Exploits.start({ client = client, shared = Shared }) -- In this frame, so the ESP hears the first slot table
local view: View.View = View.new(client, Config.view, cast)
local mantle: TextLabel? = nil -- The prompt, once the PlayerGui it waits for has come
local button: Part = elevator(client)

-- The press's ray meets the elevator's button and the world the server's own cast of the press meets
local reached: { Instance } = table.clone(include)
table.insert(reached, button)

local pressParams: RaycastParams = RaycastParams.new()
pressParams.FilterType = Enum.RaycastFilterType.Include
pressParams.FilterDescendantsInstances = reached

Camera.CameraType = Enum.CameraType.Scriptable

-- Every connection below lives for the client session
RunService.PreRender:Connect(function (dt: number)
	local eye: Vector3, look: Vector3 = client:getEye()
	Camera.CFrame = CFrame.lookAlong(view:frame(dt, eye, look), look)

	-- Set every frame rather than once, so a lock anything else lets go of comes back
	if UserInputService.MouseEnabled then
		UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
	end

	-- Shown exactly while a jump press now would start a mantle
	local label: TextLabel? = mantle
	if label then
		label.Visible = client:getMantle() ~= nil
	end
end)

-- The view switches on its key, and a press while it blends turns it back. The elevator's key sends the press when a
-- ray from the eye along the look meets the button within reach before any world part, as the server checks again
UserInputService.InputBegan:Connect(function (pressed: InputObject, processed: boolean)
	if processed then
		return
	elseif pressed.KeyCode == VIEW_KEY then
		view:toggle()
	elseif pressed.KeyCode == PRESS_KEY then
		local eye: Vector3, look: Vector3 = client:getEye()
		local hit: RaycastResult? = Workspace:Raycast(eye, look * Elevator.reach, pressParams)
		if hit and hit.Instance == button then
			Network.press.fire(Elevator.platform.id)
		end
	end
end)

-- The local player's new body turns the look to face the way the server built it
client:onSpawned(function (slot: Tread.Slot, _: Model)
	local state: Tread.State? = client:getState()
	if slot.player == Player and state then
		input:face(state.facing)
	end
end)

-- The dev server counts G2's small and large corrections from each replay's size
client:onCorrected(function (size: number, flagged: boolean)
	Network.corrected.fire(size, flagged)
end)

-- Last, since each waits at boot for the PlayerGui, the input on a touch screen alone
input:start()
mantle = prompt()
