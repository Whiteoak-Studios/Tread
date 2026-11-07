--[[
    A rider's sample holds its platform's id and its place in the
    platform's frame, which a read gives back with its shapes placed in that
    frame, and a read between a sample on a platform and one off it answers
    the earlier sample, since the two places sit in different frames
--]]

--!strict
local Environment = require("../../Environment")

local HISTORY: string = "src/Server/History.luau"
local STATE: string = "src/Step/State.luau"
local EXAMPLE: string = "tests/Fixtures/Config/Example.luau"
local SLOT: number = 4
local PLATFORM: number = 5
local LIFT: vector = vector.create(100, 10, 50) -- The platform's place at the first tick, rising a stud a tick
local OFFSET: vector = vector.create(10, 0.5, -2) -- The rider's place on it
local LEGS_BOTTOM: number = 0.4 -- The standing legs' bottom in the example's hit shapes, below its waist

return function (): (boolean, string | nil)
	local History: any = Environment.load(HISTORY)
	local State: any = Environment.load(STATE)
	local Example: any = Environment.load(EXAMPLE)
	History.start(Example.shared(), Example.server())

	local state = State.new()
	state.platform = PLATFORM

	for tick: number = 1, 3 do
		local lift: vector = LIFT + vector.create(0, tick - 1, 0)
		state.position = lift + OFFSET
		History.write(SLOT, tick, state, 0, lift)
	end

	-- Stepped off onto the world at tick 4
	state.platform = 0
	state.position = vector.create(115, 13.5, 48)
	History.write(SLOT, 4, state, 0)

	for _, time: number in { 1, 2.5, 3 } do
		local sample = History.sampleAt(SLOT, time)
		if sample == nil or sample.platform ~= PLATFORM or sample.position ~= OFFSET then
			local got: string = `{sample and sample.position} on platform {sample and sample.platform}`
			return false, `At {time} the rider read {got}, not {OFFSET} on platform {PLATFORM}`
		end

		local legs: vector = sample.zones.legs.from
		if legs ~= OFFSET + vector.create(0, LEGS_BOTTOM, 0) then
			return false, `At {time} the rider's legs sat at {legs}, not in the platform's frame at its feet`
		end
	end

	local stepping = History.sampleAt(SLOT, 3.5)
	if stepping == nil or stepping.platform ~= PLATFORM or stepping.position ~= OFFSET then
		local got: string = `{stepping and stepping.position} on platform {stepping and stepping.platform}`
		return false, `Between the last sample on the platform and the first off it the rider read {got}`
	end

	local off = History.sampleAt(SLOT, 4)
	if off == nil or off.platform ~= 0 or off.position ~= vector.create(115, 13.5, 48) then
		return false, `Off the platform the body read {off and off.position} on platform {off and off.platform}`
	end

	return true, nil
end
