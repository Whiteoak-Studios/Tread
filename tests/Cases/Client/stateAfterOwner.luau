--[[
    The local character's state is nil until the first OwnerState of its
    own slot, then filled from it on Vector3 and CFrame, with getEye giving
    the same eye and look once a frame draws it
--]]

--!strict
local roblox: any = require("@lune/roblox") -- Its typedefs leave out the datatypes

local Handle = require("../../Fixtures/Client/Handle")

local Vector3: any = roblox.Vector3

local SLOT: number = 12
local GENERATION: number = 1
local COMMAND: number = 40
local TICK: number = 300
local HEADROOM: number = 1e-6 -- How far a float32 Vector3 may sit from the vector it was copied from

return function (): (boolean, string | nil)
	local rig: any = Handle.new()
	local handle: any = rig.handle
	local at: vector = vector.create(10, 20, -30)

	rig.handshake()
	if handle:getState() ~= nil then
		return false, "The client had a state before any OwnerState"
	end

	-- An OwnerState before the slot table names our slot belongs to no body of ours
	rig.owner(rig.body(at, COMMAND, TICK))
	if handle:getState() ~= nil then
		return false, "An OwnerState before the slot table named our slot started a body"
	end

	rig.own(SLOT, GENERATION)
	if handle:getState() ~= nil then
		return false, "The client had a state once its slot was named but before any OwnerState"
	end

	local eye: Vector3, look: Vector3 = handle:getEye()
	if eye ~= Vector3.zero or look ~= Vector3.new(0, 0, -1) then
		return false, `With no body the eye was {eye} looking {look}, not the origin looking along -Z`
	end

	rig.owner(rig.body(at, COMMAND, TICK + 1))

	local state: any = handle:getState()
	if state == nil then
		return false, "The first OwnerState of our slot left the client with no state"
	elseif typeof(state.root) ~= "Vector3" or typeof(state.standingBox.cframe) ~= "CFrame" then
		return false, `The state's root is a {typeof(state.root)} and its box a {typeof(state.standingBox.cframe)}`
	elseif (state.root - Vector3.new(at.x, at.y, at.z)).Magnitude > HEADROOM then
		return false, `The state's root is {state.root}, where the OwnerState put the body at {at}`
	elseif state.hullCenter.Y <= state.root.Y then
		return false, `The hull's center {state.hullCenter} sits no higher than the feet {state.root}`
	end

	-- A frame of no time finds the body's eye without moving it, and getEye gives what the frame found
	rig.frames(1, 0)
	local drawnEye: Vector3, drawnLook: Vector3 = handle:getEye()
	if drawnEye ~= state.eye or drawnLook ~= state.look then
		return false,
			`getEye gave {drawnEye} looking {drawnLook}, where the state holds {state.eye} looking {state.look}`
	elseif handle:getState() ~= state then
		return false, "A second getState handed back another table"
	end

	return true, nil
end
