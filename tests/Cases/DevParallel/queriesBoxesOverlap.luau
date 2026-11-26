--[[
    The overlap probe's boxes and answers: count boxes at the hull's size,
    the same twice, those inside a face overlapping it and the rest not,
    and the comparison finding a flipped answer and a short run
--]]

--!strict
local roblox: any = require("@lune/roblox") -- Its typedefs leave out the datatypes

local Harness = require("../../Fixtures/DevServer/Harness")

local SEED: number = 362436069
local COUNT: number = 26 -- Two turns of the 13 gaps
local INSIDE: number = 12 -- Of them, those whose gap is below 0: six a turn
local BOX_WIDTH: number = 6 -- A box's center and size
local F64_BYTES: number = 8
local SIZE: number = 3 -- A box's size, from 0 in its record
local AXES: number = 3
local HULL: { number } = { 2, 5, 2 } -- Halves of 1, 2.5 and 1, so a box touching a face sums exactly
local SLOT_CENTER: { number } = { 0, 10, 0 }
local SLOT_HALF: number = 2 -- The slot is a 4-stud cube
local OVERLAPPED: string = "3ff0000000000000" -- The bits of 1 and of 0
local CLEAR: string = "0000000000000000"

local function value(boxes: buffer, box: number, field: number): number
	return buffer.readf64(boxes, ((box - 1) * BOX_WIDTH + field) * F64_BYTES)
end

-- Whether a box and the slot share any volume, touching faces left out
local function overlap(center: vector, size: vector): boolean
	local reach: { number } = { size.x / 2, size.y / 2, size.z / 2 }
	local at: { number } = { center.x, center.y, center.z }
	for axis: number = 1, AXES do
		if math.abs(at[axis] - SLOT_CENTER[axis]) >= SLOT_HALF + reach[axis] then
			return false
		end
	end

	return true
end

return function (): (boolean, string | nil)
	local loaded: any = Harness.load()
	local Queries: any = loaded.require(loaded.game:GetService("ServerScriptService").Server.Parallel.Queries)

	local slot: any = roblox.Instance.new("Part")
	slot.Size = roblox.Vector3.new(SLOT_HALF * 2, SLOT_HALF * 2, SLOT_HALF * 2)
	slot.CFrame = roblox.CFrame.new(SLOT_CENTER[1], SLOT_CENTER[2], SLOT_CENTER[3])

	local hull: any = roblox.Vector3.new(HULL[1], HULL[2], HULL[3])
	local boxes: buffer = Queries.boxes({ slot }, hull, COUNT, SEED)

	-- 1) Count boxes, each at the hull's size, and the same bytes from the same inputs
	if buffer.len(boxes) ~= COUNT * BOX_WIDTH * F64_BYTES then
		return false, `{COUNT} boxes took {buffer.len(boxes)} B`
	end

	for box: number = 1, COUNT do
		for axis: number = 1, AXES do
			if value(boxes, box, SIZE + axis - 1) ~= HULL[axis] then
				return false, `Box {box} is {value(boxes, box, SIZE + axis - 1)} studs on axis {axis}, not {HULL[axis]}`
			end
		end
	end

	if buffer.tostring(Queries.boxes({ slot }, hull, COUNT, SEED)) ~= buffer.tostring(boxes) then
		return false, "Two sets of boxes from the same inputs differ"
	end

	-- 2) The boxes inside a face overlap the slot and the rest, touching or clear, do not
	local answers: buffer = Queries.overlaps(boxes, overlap)
	local tally: any = Queries.compareOverlaps(answers, answers)
	if tally.boxes ~= COUNT or tally.overlapping ~= INSIDE or tally.differing ~= 0 or tally.missing ~= 0 then
		local counts: string = `{tally.overlapping} overlapping, {tally.differing} differing, {tally.missing} missing`
		return false, `{COUNT} boxes against themselves gave {tally.boxes} boxes, {counts}`
	elseif tally.first ~= nil then
		return false, `Equal answers gave a first difference, "{tally.first}"`
	end

	-- 3) The first box, inside its face by the first gap, answered clear on their side is one difference
	local flipped: buffer = buffer.create(buffer.len(answers))
	buffer.copy(flipped, 0, answers)
	buffer.writef64(flipped, 0, 0)

	tally = Queries.compareOverlaps(answers, flipped)
	local first: string = `box 1: ours {OVERLAPPED}, theirs {CLEAR}`
	if tally.differing ~= 1 or tally.missing ~= 0 or tally.first ~= first then
		return false, `A flipped first box gave {tally.differing} differing, {tally.missing} missing, "{tally.first}"`
	end

	-- 4) Their answers one box short is that box missing
	local short: buffer = buffer.create(buffer.len(answers) - F64_BYTES)
	buffer.copy(short, 0, answers, 0, buffer.len(short))

	tally = Queries.compareOverlaps(answers, short)
	first = `box {COUNT}: ours holds {COUNT} answers and theirs {COUNT - 1}`
	if tally.boxes ~= COUNT or tally.differing ~= 1 or tally.missing ~= 1 or tally.first ~= first then
		return false, `A short run gave {tally.boxes} boxes, {tally.differing} differing, "{tally.first}"`
	end

	return true, nil
end
