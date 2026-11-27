--[[
    State.copy copies every field of one state into another, the game's blocks
    into into's own tables, nested ones reused, and clears keys from lacks
--]]

--!strict
local roblox: any = require("@lune/roblox") -- Its typedefs leave out the datatypes

local Environment = require("../../Environment")

local STATE: string = "src/Step/State.luau"

-- A value for every field of Tread's own, none of them State.new's
local SET: { [string]: any } = {
	command = 41,
	tick = 977,
	depth = 2,
	position = vector.create(10.5, 1100.25, -3),
	velocity = vector.create(4, -12.5, 0.25),
	facing = 1.25,
	mode = "Ladder",
	posture = "Crouch",
	sprint = true,
	aim = true,
	waterLevel = "Wading",
	jumps = 3,
	lands = 2,
	heavy = true,
	epoch = 200,
	platform = 7,
	moveMode = "Noclip",
	grounded = true,
	lean = -12,
	eyeHeight = 2.5,
	apex = 1130.5,
	groundHeight = 1101.5,
	groundTicks = 9,
	airTicks = 4,
	mantleTicks = 6,
	slideCooldown = 33,
	mantleRise = 3.5,
	ladder = 12,
	groundNormal = vector.create(0, 1, 0),
	groundMaterial = roblox.Enum.Material.Grass,
	npc = true,
}

return function (): (boolean, string | nil)
	local State: any = Environment.load(STATE)

	local from: { [string]: any } = State.new()
	for field: string, value: any in SET do
		from[field] = value
	end

	from.fields.beingRevived = true
	from.block.sinceJump = 3
	from.block.shots = { { yaw = 10 }, { yaw = 20 } }
	from.held.item = 4

	local into: { [string]: any } = State.new()
	local intoFields: { [string]: any } = into.fields
	into.held.skin = 9 -- Absent from from, so the copy clears it

	State.copy(from, into)

	for field: string, value: any in SET do
		if into[field] ~= value then
			return false, `State.copy left {field} at {into[field]}, where {value} was copied`
		end
	end

	-- Every field the step state holds was set above, its three game blocks aside
	for field: string in from do
		local block: boolean = field == "fields" or field == "block" or field == "held"
		if SET[field] == nil and not block then
			return false, `This case sets no value for {field}, so it proves nothing about copying it`
		end
	end

	if into.fields ~= intoFields then
		return false, "State.copy replaced into's fields table instead of copying into it"
	elseif into.block == from.block or into.block.shots == from.block.shots then
		return false, "State.copy shared a game block's table between the two states"
	elseif into.fields.beingRevived ~= true or into.block.sinceJump ~= 3 or into.held.item ~= 4 then
		return false, "State.copy dropped a game field"
	elseif into.held.skin ~= nil then
		return false, "State.copy kept a held field the copied state lacks"
	elseif #into.block.shots ~= 2 or into.block.shots[2].yaw ~= 20 then
		return false, "State.copy dropped a nested game value"
	end

	-- A second copy writes into the nested tables the first made, and a shorter list loses its tail
	local shots: { any } = into.block.shots
	local firstShot: { [string]: any } = shots[1]
	from.block.shots = { { yaw = 30 } }
	State.copy(from, into)

	if into.block.shots ~= shots or into.block.shots[1] ~= firstShot then
		return false, "A second State.copy made new nested tables where into already held them"
	elseif #into.block.shots ~= 1 or into.block.shots[1].yaw ~= 30 then
		return false, "A second State.copy left the nested list's old values"
	end

	-- A change to into after the copy reaches nothing of from's
	into.block.sinceJump = 0
	into.block.shots[1].yaw = 0
	if from.block.sinceJump ~= 3 or from.block.shots[1].yaw ~= 30 then
		return false, "A change to the copy reached the state it was copied from"
	end

	return true, nil
end
