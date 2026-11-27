--[[
    A moving character inside the near tier is sent every relay tick and
    one in the far tier at 15 Hz; past the soft budget each falls to its
    floor and no lower, past the hard one nothing goes, and the tier keeps
    to its 200-stud entry and 220-stud exit
--]]

--!strict
local Environment = require("../../Environment")

local HARNESS: string = "tests/Fixtures/Relay/Harness.luau"
local TICKS: number = 20 -- A second at the example's 20 Hz relay
local NEAR_AIM: number = 20
local FAR_AIM: number = 15
local NEAR_FLOOR: number = 15
local FAR_FLOOR: number = 10
local SLACK: number = 1 -- How far a second's count may sit off its rate, by where its tier ticks fall
local SOFT: number = 64 * 1000 -- The example's budgets, in bytes a second
local HARD: number = 96 * 1000
local STRIDE: number = 0.5

return function (): (boolean, string | nil)
	local Harness: any = Environment.load(HARNESS)
	local harness: any = Harness.new()
	local client: any = harness:viewer("Viewer")
	local near: number = harness:spawn("Player", vector.create(100, 0, 0))
	local far: number = harness:spawn("Player", vector.create(500, 0, 0))

	-- Records each character gets over a second, each moving a little every tick
	local function second(): (number, number)
		local nearCount: number, farCount: number = 0, 0

		for _ = 1, TICKS do
			harness.states[near].position += vector.create(0, 0, STRIDE)
			harness.states[far].position += vector.create(0, 0, STRIDE)
			harness:run()

			nearCount += Harness.count(client.seen.records, near)
			farCount += Harness.count(client.seen.records, far)
		end

		return nearCount, farCount
	end

	harness:run()

	local nearCount: number, farCount: number = second()
	if nearCount ~= NEAR_AIM or farCount ~= FAR_AIM then
		return false, `Inside the budget a second gave {nearCount} near and {farCount} far records, not 20 and 15`
	end

	-- Past the soft budget only what each floor owes goes
	harness.traffic = SOFT + 1
	nearCount, farCount = second()

	if math.abs(nearCount - NEAR_FLOOR) > SLACK or math.abs(farCount - FAR_FLOOR) > SLACK then
		return false, `Past the soft budget a second gave {nearCount} near and {farCount} far records, not 15 and 10`
	end

	harness.traffic = HARD
	nearCount, farCount = second()
	if nearCount + farCount ~= 0 then
		return false, `At the hard budget {nearCount + farCount} records still went`
	end

	-- The near tier is left only past 220 studs and entered again only inside 200
	harness.traffic = 0
	harness.states[near].position = vector.create(210, 0, 0)
	nearCount = second()
	if nearCount ~= NEAR_AIM then
		return false, `At 210 studs, inside the near tier's exit, a second gave {nearCount} records, not 20`
	end

	harness.states[near].position = vector.create(225, 0, 0)
	nearCount = second()
	if math.abs(nearCount - FAR_AIM) > SLACK then
		return false, `At 225 studs, past the near tier's exit, a second gave {nearCount} records, not 15`
	end

	harness.states[near].position = vector.create(205, 0, 0)
	nearCount = second()
	if math.abs(nearCount - FAR_AIM) > SLACK then
		return false, `At 205 studs, outside the near tier's entry, a second gave {nearCount} records, not 15`
	end

	return true, nil
end
