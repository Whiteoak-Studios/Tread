--[[
    A ladder's id is the low 16 bits of the FNV-1a over its box's numbers at
    the 1/512 quantum, so the same boxes take the same ids in either order,
    a zero's sign and a nudge under half a quantum change nothing, and a
    box whose low bits are 0 takes 1
--]]

--!strict
local roblox: any = require("@lune/roblox") -- Its typedefs leave out the datatypes

local Environment = require("../../Environment")

local WORLD: string = "src/Step/World.luau"
local HASH: string = "src/Codec/Hash.luau"
local MATH: string = "src/Step/Math.luau"
local SCENE: string = "tests/Fixtures/Step/Scene.luau"
local CASTS: string = "tests/Fixtures/Step/Collision.luau"
local IDS: number = 2 ^ 16 -- The ids OwnerState's u16 ladder field holds
local F64_BYTES: number = 8
local NUDGE: number = 1 / 4096 -- Under half of the 1/512 quantum

-- A box found by search whose numbers hash to 251330560, whose low 16 bits are 0
local ZERO_AT: Vector3 = roblox.Vector3.new(1102, 1100, 282)

local function rules(_: any, _: any): number
	return math.huge
end

return function (): (boolean, string | nil)
	local World: any = Environment.load(WORLD)
	local Hash: any = Environment.load(HASH)
	local Math: any = Environment.load(MATH)
	local Scene: any = Environment.load(SCENE)
	local Casts: any = Environment.load(CASTS)

	local function newWorld(): any
		return World.new(Scene.settings, 20, Casts({}), nil, rules, true)
	end

	-- The low 16 bits of a box's hash, worked out here from its CFrame and size
	local function lowBits(cframe: any, size: any): number
		local data: buffer = buffer.create(15 * F64_BYTES)
		local offset: number = 0

		for _, value: any in { cframe.Position, cframe.RightVector, cframe.UpVector, cframe.LookVector, size } do
			for _, axis: number in { value.X, value.Y, value.Z } do
				buffer.writef64(data, offset, Math.quantize(axis) + 0)
				offset += F64_BYTES
			end
		end

		return Hash.range(data, 0, offset) % IDS
	end

	-- The id World gives a box registered alone
	local function idOf(cframe: any, size: any): number
		local world: any = newWorld()
		World.addLadder(world, cframe, size)

		return world.ladders[1].id
	end

	local size: any = roblox.Vector3.new(0.5, 10, 2)
	local first: any = roblox.CFrame.new(1, 1102, 3) * roblox.CFrame.Angles(0, math.pi / 2, 0)
	local second: any = roblox.CFrame.new(7, 1102, -4)

	local forward: any = newWorld()
	World.addLadder(forward, first, size)
	World.addLadder(forward, second, size)

	local backward: any = newWorld()
	World.addLadder(backward, second, size)
	World.addLadder(backward, first, size)

	local firstId: number, secondId: number = forward.ladders[1].id, forward.ladders[2].id
	if backward.ladders[2].id ~= firstId or backward.ladders[1].id ~= secondId then
		return false, "the same two boxes took other ids registered in the other order"
	elseif firstId == secondId or firstId == 0 or secondId == 0 then
		return false, `two boxes took the ids {firstId} and {secondId}`
	elseif firstId ~= lowBits(first, size) or secondId ~= lowBits(second, size) then
		return false, `the ids {firstId} and {secondId} are not the low 16 bits of their boxes' hash`
	end

	-- The same turn either way leaves its near-zero axes on opposite signs, which the quantum rounds to zeros
	local turned: any = roblox.CFrame.new(1, 1102, 3) * roblox.CFrame.Angles(0, math.pi, 0)
	local unturned: any = roblox.CFrame.new(1, 1102, 3) * roblox.CFrame.Angles(0, -math.pi, 0)
	if idOf(turned, size) ~= idOf(unturned, size) then
		return false, "a half turn either way took two ids"
	end

	local signed: any = roblox.CFrame.new(-0, 1102, 3)
	local unsigned: any = roblox.CFrame.new(0, 1102, 3)
	if idOf(signed, size) ~= idOf(unsigned, size) then
		return false, "a box at x -0 and one at x 0 took two ids"
	end

	local nudged: any = roblox.CFrame.new(7 + NUDGE, 1102, -4)
	if idOf(nudged, size) ~= secondId then
		return false, "a box nudged under half a quantum took another id"
	end

	local zero: any = roblox.CFrame.new(ZERO_AT.X, ZERO_AT.Y, ZERO_AT.Z)
	local zeroId: number = idOf(zero, size)
	if lowBits(zero, size) ~= 0 then
		return false, "the box found by search no longer has low bits of 0, so the skip goes untested"
	elseif zeroId ~= 1 then
		return false, `the box whose low bits are 0 took the id {zeroId}, where 1 was expected`
	end

	return true, nil
end
