--[[
    Public.fill fills every field of a public state in place from a fixed
    step state at each posture, the hull center and both boxes' CFrames and
    sizes number by number at each quarter facing and one between them
--]]

--!strict
local roblox: any = require("@lune/roblox") -- Its typedefs leave out the datatypes

local Environment = require("../../Environment")

local PUBLIC: string = "src/Step/Public.luau"
local MATH: string = "src/Step/Math.luau"
local SCENE: string = "tests/Fixtures/Step/Scene.luau"

local FEET: vector = vector.create(-20.25, 1100.01953125, 37.5)
local VELOCITY: vector = vector.create(3.5, -12.25, 0.75)
local NORMAL: vector = vector.create(0.6, 0.8, 0) -- A slope, so no field reads as the default up
local EYE: vector = vector.create(-20.5, 1104.15625, 37.25)
local APEX: number = 1104.5
local PLATFORM: number = 3
local EPOCH: number = 9
local BETWEEN: number = 0.6 -- A facing off every axis, in radians
local CLOSE: number = 1e-7 -- A float32 rotation entry against the C library's trig

-- The command look the handle hands in: a pitch in radians and a head offset in degrees
local PITCH: number = 0.25
local HEAD_YAW: number = 10
local HEAD_PITCH: number = -5

-- Frontier Zero's hull heights and its lying box, as the scene's settings give them
local STANDING: number = 5
local CROUCHED: number = 3.06
local LYING_SIZE: vector = vector.create(2, 2, 5) -- Width across the facing, height, length along it
local LIFT: number = 1

type Facing = {
	angle: number,
	rotation: { number }?, -- The nine entries exactly, row by row, where a quarter facing gives them
	look: vector?, -- The CFrame's look exactly
}

type Row = { posture: string, height: number }

local FACINGS: { Facing } = {
	{ angle = 0, rotation = { 1, 0, 0, 0, 1, 0, 0, 0, 1 }, look = vector.create(0, 0, -1) },
	{ angle = math.pi / 2, rotation = { 0, 0, 1, 0, 1, 0, -1, 0, 0 }, look = vector.create(-1, 0, 0) },
	{ angle = math.pi, rotation = { -1, 0, 0, 0, 1, 0, 0, 0, -1 }, look = vector.create(0, 0, 1) },
	{ angle = 3 * math.pi / 2, rotation = { 0, 0, -1, 0, 1, 0, 1, 0, 0 }, look = vector.create(1, 0, 0) },
	{ angle = BETWEEN },
}

-- Stand last, so a posture the fill never wrote would still read the row before it
local POSTURES: { Row } = {
	{ posture = "Crouch", height = CROUCHED },
	{ posture = "Downed", height = CROUCHED },
	{ posture = "Stand", height = STANDING },
}

-- A number as a float32 holds it, which every Vector3 and CFrame component is
local function f32(value: number): number
	return vector.create(value, 0, 0).x
end

local function same(got: any, want: vector): boolean
	return got.X == want.x and got.Y == want.y and got.Z == want.z
end

--[[
    Checks a box's CFrame and size number by number: its position, its nine
    rotation entries against the facing's, exactly at a quarter facing and to
    float32 at any other, its look along the facing, and its size
--]]

local function checkBox(name: string, box: any, at: vector, size: vector, facing: Facing): (boolean, string | nil)
	if typeof(box.cframe) ~= "CFrame" or typeof(box.size) ~= "Vector3" then
		return false, `The {name}'s cframe and size are a {typeof(box.cframe)} and a {typeof(box.size)}`
	end

	local components: { number } = { box.cframe:GetComponents() }
	local x: number, y: number, z: number = components[1], components[2], components[3]
	if x ~= at.x or y ~= at.y or z ~= at.z then
		return false, `At facing {facing.angle} the {name} sat at {x}, {y}, {z}, not {at}`
	end

	local sine: number, cosine: number = math.sin(facing.angle), math.cos(facing.angle)
	local wanted: { number } = facing.rotation or { cosine, 0, sine, 0, 1, 0, -sine, 0, cosine }
	local tolerance: number = facing.rotation and 0 or CLOSE

	for index: number, want: number in wanted do
		local got: number = components[index + 3]
		if math.abs(got - want) > tolerance then
			return false, `At facing {facing.angle} the {name}'s rotation entry {index} was {got}, not {want}`
		end
	end

	local look: any = box.cframe.LookVector
	local along: vector = facing.look or vector.create(-sine, 0, -cosine)
	if
		math.abs(look.X - along.x) > tolerance
		or math.abs(look.Y - along.y) > tolerance
		or math.abs(look.Z - along.z) > tolerance
	then
		return false, `At facing {facing.angle} the {name} looked along {look}, not {along}`
	end

	if not same(box.size, size) then
		return false, `The {name} was sized {box.size}, not {size}`
	end

	return true, nil
end

return function (): (boolean, string | nil)
	local Public: any = Environment.load(PUBLIC)
	local Math: any = Environment.load(MATH)
	local Scene: any = Environment.load(SCENE)

	local world: any = Scene.world({})
	local radius: number = Scene.settings.radius
	local grass: any = roblox.Enum.Material.Grass

	local into: any = Public.new()
	local standingBox: any, lyingBox: any = into.standingBox, into.lyingBox

	for _, row: Row in POSTURES do
		for _, facing: Facing in FACINGS do
			local state: any = Scene.state(FEET, true)
			state.velocity = VELOCITY
			state.facing = facing.angle
			state.posture = row.posture
			state.moveMode = "Parked"
			state.groundNormal = NORMAL
			state.groundMaterial = grass
			state.apex = APEX
			state.platform = PLATFORM
			state.epoch = EPOCH

			local look: vector = Public.look(facing.angle, PITCH, HEAD_YAW, HEAD_PITCH, Scene.settings.headCone)
			Public.fill(into, state, world, EYE, look)

			local where: string = `At {row.posture} and facing {facing.angle}`
			local fields: { [string]: any } = {
				facing = facing.angle,
				grounded = true,
				groundMaterial = grass,
				mode = "Ground",
				posture = row.posture,
				moveMode = "Parked",
				apex = APEX,
				platform = PLATFORM,
				epoch = EPOCH,
			}

			for field: string, want: any in fields do
				if into[field] ~= want then
					return false, `{where} the public {field} was {into[field]}, not {want}`
				end
			end

			local vectors: { [string]: vector } = {
				root = FEET,
				velocity = VELOCITY,
				groundNormal = NORMAL,
				eye = EYE,
				look = look,
			}

			for field: string, want: vector in vectors do
				local got: any = into[field]
				if typeof(got) ~= "Vector3" or not same(got, want) then
					return false, `{where} the public {field} was {got}, not {want}`
				end
			end

			local center: vector = vector.create(FEET.x, f32(FEET.y + row.height / 2), FEET.z)
			if typeof(into.hullCenter) ~= "Vector3" or not same(into.hullCenter, center) then
				return false, `{where} the hull center was {into.hullCenter}, not {center}`
			end

			if into.standingBox ~= standingBox or into.lyingBox ~= lyingBox then
				return false, `{where} the fill made new box tables, where it fills the ones it was handed`
			end

			local width: number = f32(radius + radius)
			local hull: vector = vector.create(width, row.height, width)
			local fine: boolean, why: string? = checkBox("standing box", standingBox, center, hull, facing)
			if not fine then
				return false, `{where}: {why}`
			end

			local raised: vector = vector.create(FEET.x, FEET.y + LIFT, FEET.z)
			fine, why = checkBox("lying box", lyingBox, raised, LYING_SIZE, facing)
			if not fine then
				return false, `{where}: {why}`
			end

			-- The rotation is the step's own trig, so a box's entries are Math.sin and Math.cos of the facing exactly
			local _, _, _, r00: number, _, r02: number = standingBox.cframe:GetComponents()
			if r00 ~= f32(Math.cos(facing.angle)) or r02 ~= f32(Math.sin(facing.angle)) then
				return false, `{where} the standing box's rotation was not the step's own cosine and sine of the facing`
			end
		end
	end

	return true, nil
end
