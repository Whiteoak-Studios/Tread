--[[
    getMantle gives nil before the first OwnerState and once the local
    player's slot is freed, and while the body faces a ledge a press would
    mantle onto, the point the press's own search ends at, on a Vector3
--]]

--!strict
local roblox: any = require("@lune/roblox") -- Its typedefs leave out the datatypes

local Environment = require("../../Environment")
local Handle = require("../../Fixtures/Client/Handle")

local Vector3: any = roblox.Vector3

local COLLISION: string = "tests/Fixtures/Step/Collision.luau"
local GEOMETRY: string = "tests/Fixtures/Step/Geometry.luau"
local MATH: string = "src/Step/Math.luau"
local SLOT: number = 12
local GENERATION: number = 1
local COMMAND: number = 40
local TICK: number = 300
local EAST: number = -math.pi / 2 -- A yaw that looks along +X, at the riser's west face
local RISE: number = 1.03125 -- From feet resting on the floor to a skin over the 1-stud riser, on the rise's 1/32 steps

return function (): (boolean, string | nil)
	local rig: any = Handle.new()
	local handle: any = rig.handle
	local Geometry: any = Environment.load(GEOMETRY)
	local Math: any = Environment.load(MATH)
	local settings: any = rig.shared.step
	local skin: number = rig.Constants.SKIN

	-- Prediction's world casts against the step fixture's parts, the riser among them
	handle._world.collision = Environment.load(COLLISION)(Geometry.parts)

	rig.handshake()
	rig.own(SLOT, GENERATION)

	local ran: boolean, early: any = pcall(handle.getMantle, handle)
	if not ran or early ~= nil then
		return false, `getMantle before the first OwnerState gave {early}, where nil was expected`
	end

	-- A body standing a skin from the riser's west face, looking at it
	local riser: any = Geometry.riser
	local face: number = riser.center.x - riser.size.x / 2
	local resting: number = Math.quantize(Geometry.floor + skin)
	local at: vector = vector.create(Math.quantize(face - settings.radius - skin), resting, riser.center.z)
	local body: any = rig.body(at, COMMAND, TICK)
	body.mode = "Ground"
	body.grounded = true
	body.facing = EAST
	body.groundHeight = resting
	rig.owner(body)

	local point: any = handle:getMantle()
	local over: number = Math.quantize(2 * settings.radius + 2 * skin)
	local expected: any = Vector3.new(at.x + over, resting + RISE, riser.center.z)
	if typeof(point) ~= "Vector3" then
		return false, `getMantle facing the riser gave a {typeof(point)}, not a Vector3`
	elseif point ~= expected then
		return false, `getMantle facing the riser gave {point}, where the path ends at {expected}`
	end

	-- The slot freed ends the body, and with it any mantle
	rig.slots({ { slot = SLOT, generation = GENERATION, rig = nil } })
	if handle:getMantle() ~= nil then
		return false, "getMantle gave a point after the local player's slot was freed"
	end

	return true, nil
end
