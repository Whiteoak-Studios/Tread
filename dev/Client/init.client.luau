--[[
    The dev place's client: starts Tread's client as a game does, with the
    dev game's shared table and Frontier Zero's client settings, then the
    input, the first-person camera on Tread's eye and the corrections G2 counts
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
local Input = require(script.Input)
local Rig = require(script.Rig)
local Shared = require(ReplicatedStorage.Shared.Dev.Config)

local Camera = Workspace.CurrentCamera

local input = Input.new()

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

Camera.CameraType = Enum.CameraType.Scriptable

-- Every connection below lives for the client session
RunService.PreRender:Connect(function ()
	local eye: Vector3, look: Vector3 = client:getEye()
	Camera.CFrame = CFrame.lookAlong(eye, look)

	-- Set every frame rather than once, so a lock anything else lets go of comes back
	if UserInputService.MouseEnabled then
		UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
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

-- Last, since on a touch screen it waits at boot for the PlayerGui
input:start()
