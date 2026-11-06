--[[
    Each relay tick's sample answers for that tick: a body written at six
    ticks reads back each one's place, yaw and epoch at the record's
    precision, and a slot no write named answers nil
--]]

--!strict
local Environment = require("../../Environment")

local HISTORY: string = "src/Server/History.luau"
local STATE: string = "src/Step/State.luau"
local EXAMPLE: string = "tests/Fixtures/Config/Example.luau"
local SLOT: number = 7
local FIRST: number = 100 -- The first relay tick written
local TICKS: number = 6
local TURN_STEP: number = math.pi / 8 -- Each tick's yaw step, a whole count of the u16's steps
local NEAR: number = 1e-9

return function (): (boolean, string | nil)
	local History: any = Environment.load(HISTORY)
	local State: any = Environment.load(STATE)
	local Example: any = Environment.load(EXAMPLE)
	History.start(Example.shared(), Example.server())

	local state = State.new()

	for index: number = 0, TICKS - 1 do
		state.position = vector.create(10 + index * 0.5, 4 + index * 0.25, -20 - index * 0.125)
		state.facing = index * TURN_STEP
		state.epoch = index
		History.write(SLOT, FIRST + index, state, 0)
	end

	for index: number = 0, TICKS - 1 do
		local tick: number = FIRST + index
		local sample = History.sampleAt(SLOT, tick)
		if sample == nil then
			return false, `Tick {tick} answered nil, though it was written`
		end

		local want: vector = vector.create(10 + index * 0.5, 4 + index * 0.25, -20 - index * 0.125)
		if sample.position ~= want then
			return false, `Tick {tick} read back at {sample.position}, not {want}`
		elseif math.abs(sample.yaw - index * TURN_STEP) > NEAR then
			return false, `Tick {tick} read back a yaw of {sample.yaw}, not {index * TURN_STEP}`
		elseif sample.epoch ~= index or sample.platform ~= 0 or sample.posture ~= "Stand" then
			return false, `Tick {tick} read back epoch {sample.epoch}, platform {sample.platform}, {sample.posture}`
		end
	end

	if History.sampleAt(SLOT + 1, FIRST) ~= nil then
		return false, `Slot {SLOT + 1}, which no write named, answered a sample`
	end

	-- A sample holds the place as a record does, at 1/64 stud across and 1/32 up
	state.position = vector.create(1.004, 2.01, -3.007)
	History.write(SLOT, FIRST + TICKS, state, 0)

	local rounded = History.sampleAt(SLOT, FIRST + TICKS)
	local want: vector = vector.create(1, 2, -3)
	if rounded == nil or rounded.position ~= want then
		return false, `A place off the record's grid read back at {rounded and rounded.position}, not {want}`
	end

	return true, nil
end
