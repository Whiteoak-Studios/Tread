--[[
    On stand-in workers the worker turns a run hands in are worked out from
    those the run before handed in, not from every worker viewer, and a run
    that handed none in tells the next nothing, so the next hands every one
    in
--]]

--!strict
local Environment = require("../../Environment")
local Layouts = require("../../Fixtures/Relay/Layouts")
local StandIn = require("../../Fixtures/Relay/StandIn")

local WIRE: string = "src/Server/Relay/Wire.luau"
local VIEWERS: number = 16 -- So a run may leave 4
local BUDGET: number = 12 -- Stand-in seconds
local SPACING: number = 10 -- Studs between the viewers along x
local NONE_BUDGET: number = 1 -- The second part's stand-in budget, which its one-second reads pass
local NONE_STEP: number = 1
local LATER: number = 4 -- Worker viewers that join after the run that handed none in, so it may leave 1

-- Each run's stand-in seconds a clock read moves on, a run's measure being two reads' worth with workers, and the turns
-- it hands in. The first hands all 16 in and measures 13.5, so the second may hand in 16 x 12 / 13.5, 14; it measures
-- 14, so the third may hand in 14 x 12 / 14 = 12 and leaves 4, where counting all 16 would give 13 and leave 3
local SCRIPT: { { step: number, handed: number } } = {
	{ step = 6.75, handed = 16 },
	{ step = 7, handed = 14 },
	{ step = 0, handed = 12 },
}

-- A stand-in pool whose sends count each round's turn viewers handed in, the counts kept in rounds by round
local function counting(rounds: { [number]: number }): any
	local Wire: any = Environment.load(WIRE)
	local pool: any = {}

	function pool.new(count: number, name: string, remote: any, settings: any): any
		local built: any = StandIn.new(count, name, remote, settings)
		local send: any = built.send
		local hands: { any } = {}

		built.send = function (self: any, worker: number, round: number, shared: buffer, own: buffer)
			rounds[round] = rounds[round] or 0
			for index: number = 1, Wire.readOwn(own, hands) do
				if hands[index].target == nil then
					rounds[round] += 1
				end
			end

			send(self, worker, round, shared, own)
		end

		return built
	end

	return pool
end

-- Why the hand-ins followed the measure otherwise than worked out above, or nil
local function measured(): string?
	local rounds: { [number]: number } = {}
	local Harness: any = Layouts.harness(counting(rounds))
	local harness: any = Harness.new(nil, nil, 1)
	for index: number = 1, VIEWERS do
		harness:viewer(`Viewer{index}`).viewer.position = vector.create(index * SPACING, 0, 0)
	end

	Harness.Relay.setBudget(BUDGET)
	for run: number, planned: { step: number, handed: number } in SCRIPT do
		harness.step = planned.step
		harness:run()

		local handed: number? = rounds[run]
		if handed ~= planned.handed then
			return `Run {run} handed in {handed} worker turns, not {planned.handed}`
		end
	end

	return nil
end

-- Why the run after one that handed no worker turn in held a turn back, or nil
local function none(): string?
	local Harness: any = Layouts.harness()
	local harness: any = Harness.new(nil, nil, 1)
	local Relay: any = Harness.Relay

	-- A target in process, and a moderator on the worker watching it, so a run dispatches with no worker turn in it
	Relay.useWorkers(false)
	local target: any = harness:viewer("Target")
	harness:run()

	Relay.useWorkers(true)
	local moderator: any = harness:viewer("Moderator")
	moderator.viewer.position = vector.create(0, 0, SPACING)
	harness:watch(moderator, target)

	Relay.setBudget(NONE_BUDGET)
	harness.step = NONE_STEP
	harness:run()

	local _, over: number = Relay.caps()
	if over ~= 1 then
		return `The run with no worker turn was judged over {over} times, not once on its measure`
	end

	for index: number = 1, LATER do
		harness:viewer(`Later{index}`).viewer.position = vector.create(index * SPACING, 0, SPACING * 2)
	end

	harness:run()
	if #harness.passed ~= 0 then
		return `The run after one that handed no worker turn in left {#harness.passed} viewers, not 0`
	end

	return nil
end

return function (): (boolean, string | nil)
	local why: string? = measured() or none()
	if why then
		return false, why
	end

	return true, nil
end
