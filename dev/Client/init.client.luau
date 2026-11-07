--[[
    The dev place's client: starts Tread's client as a game does, with the
    dev game's shared table and Frontier Zero's client settings, then the
    exploit kit, the input, the camera, the mantle prompt and G2's corrections
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
local Exploits = require(script.Exploits)
local Input = require(script.Input)
local Rig = require(script.Rig)
local View = require(script.View)
local Shared = require(ReplicatedStorage.Shared.Dev.Config)

local Camera = Workspace.CurrentCamera

local VIEW_KEY: Enum.KeyCode = Enum.KeyCode.V -- The dev place's own bind, which no game shares
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
}

local client: Tread.Client = Tread.startClient(Shared, clientSettings)
Exploits.start({ client = client, shared = Shared }) -- In this frame, so the ESP hears the first slot table
local view: View.View = View.new(client, Config.view, cast)
local mantle: TextLabel? = nil -- The prompt, once the PlayerGui it waits for has come

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

-- The view switches on the press, and a press while it blends turns it back
UserInputService.InputBegan:Connect(function (pressed: InputObject, processed: boolean)
	if not processed and pressed.KeyCode == VIEW_KEY then
		view:toggle()
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
