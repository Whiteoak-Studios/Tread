--[[
    The foot's rise decodes to the step it was bent for and its lag behind
    the latest step: each step's own rise reads 0, an older one its age round
    the rise's cycle, and a height a hair off its value reads as that value
--]]

--!strict
local Mount = require("../../Fixtures/DevClientParallel/Mount")

local RISE: { base: number, spacing: number, count: number } = { base = 0, spacing = 0.1, count = 8 }
local STEPS: number = 24 -- Steps checked, three times round the cycle
local HAIR: number = 1e-6 -- Studs a read may sit off a rise's value, as the engine's float positions put it
local CLOSE: number = 1e-12 -- Studs a height may sit from the one worked out here

-- Heights a hair under and over their values, each with the latest step and the lag it reads
type Read = { height: number, latest: number, lag: number }

local READS: { Read } = {
	{ height = 0.3 - HAIR, latest = 3, lag = 0 }, -- Step 3's, read in its own step
	{ height = 0.3 + HAIR, latest = 3, lag = 0 },
	{ height = 0.7 - HAIR, latest = 9, lag = 2 }, -- Step 7's, two steps late
	{ height = 0.7 - HAIR, latest = 8, lag = 1 }, -- And one late across the cycle's end
	{ height = 0 + HAIR, latest = 16, lag = 0 }, -- Step 16's, the cycle's start again
	{ height = 0.4 - HAIR, latest = 12, lag = 0 }, -- Step 12's, 4 round the cycle
}

return function (): (boolean, string | nil)
	local mounted: Mount.Mounted = Mount()
	local Lines: any = mounted.Lines
	local Work: any = mounted.Work

	-- 1) Each step's rise is the base, a spacing a step up the cycle, and it reads 0 steps late in its own step, then
	-- one and two late in the steps after
	for step: number = 0, STEPS - 1 do
		local height: number = Work.height(RISE, step)
		local expected: number = RISE.base + RISE.spacing * (step % RISE.count)
		if math.abs(height - expected) > CLOSE then
			return false, `Step {step}'s rise was {height}, not {expected}`
		end

		for late: number = 0, 2 do
			local lag: number = Lines.lag(height, step + late, RISE)
			if lag ~= late then
				return false, `Step {step}'s rise read {lag} steps late at step {step + late}, not {late}`
			end
		end
	end

	-- 2) Heights a hair off their value read as it
	for _, read: Read in READS do
		local lag: number = Lines.lag(read.height, read.latest, RISE)
		if lag ~= read.lag then
			return false, `A foot {read.height} up read {lag} steps late at step {read.latest}, not {read.lag}`
		end
	end

	return true, nil
end
