--[[
    AntiEsp.run refuses a server tick that is no finite whole number, after
    its earlier refusals, and takes a whole one or none, the world's clock
--]]

--!strict
local Environment = require("../../Environment")
local Refuses = require("../../Fixtures/Codec/Refuses")

local HARNESS: string = "tests/Fixtures/AntiEsp/Harness.luau"
local BUDGET: number = 0.002 -- Seconds, a slice's
local TICK: string = "the server tick as a whole number or nil"
local REFUSED: { any } = { 0 / 0, math.huge, -math.huge, 1.5, "soon" }
local TAKEN: { number } = { 0, 3, -1, 65536 } -- Whole ticks, the last past the 16-bit world tick, as the clock runs on

return function (): (boolean, string | nil)
	local Harness: any = Environment.load(HARNESS)
	local clock: any = Harness.clock()
	local harness: any = Harness.new(nil, clock.read)
	local AntiEsp: any = Harness.AntiEsp

	for _, value: any in REFUSED do
		local refused: boolean, why: string = Refuses(TICK, AntiEsp.run, BUDGET, 0, value)
		if not refused then
			return false, `AntiEsp.run on tick {value} went another way: {why}`
		elseif not string.find(why, `, not {value}`, 1, true) then
			return false, `AntiEsp.run's refusal of tick {value} named another value: {why}`
		end
	end

	-- A budget or a clock refused names itself first, and inside a hold the hold does
	local earlier: { { any } } = {
		{ "a budget in seconds", -1, 0 },
		{ "the schedule's clock", BUDGET, 0 / 0 },
	}

	for _, row: { any } in earlier do
		local refused: boolean, why: string = Refuses(row[1], AntiEsp.run, row[2], row[3], 1.5)
		if not refused then
			return false, `AntiEsp.run with a bad tick beside a bad argument went another way: {why}`
		end
	end

	AntiEsp.hold()
	local held: boolean, heldWhy: string = Refuses("inside a hold", AntiEsp.run, BUDGET, 0, 1.5)
	AntiEsp.release()
	if not held then
		return false, `AntiEsp.run inside a hold with a bad tick went another way: {heldWhy}`
	end

	for index: number, value: number in TAKEN do
		clock.reads = 0
		local ran: boolean, failure: any = pcall(AntiEsp.run, BUDGET, index, value)
		if not ran then
			return false, `AntiEsp.run refused tick {value}: {failure}`
		end
	end

	harness.world.clock = TAKEN[2]
	local ran: boolean, failure: any = pcall(AntiEsp.run, BUDGET, #TAKEN + 1)
	if not ran then
		return false, `AntiEsp.run with no tick refused: {failure}`
	end

	return true, nil
end
