--[[
    On stand-in workers a viewer the relay budget leaves gets no hand-in,
    turn or block, and each run hands in as many worker turns as the last
    run's measure allows, every one on the first run and after a measure of
    no time, and never fewer than three in four
--]]

--!strict
local Environment = require("../../Environment")
local Layouts = require("../../Fixtures/Relay/Layouts")
local StandIn = require("../../Fixtures/Relay/StandIn")

local HARNESS_WORKERS: number = 2
local WIRE: string = "src/Server/Relay/Wire.luau"
local VIEWERS: number = 8 -- So a run may leave 2
local BUDGET: number = 7 -- Stand-in seconds
local SPACING: number = 10 -- Studs between the viewers along x, which tells each hand's viewer by its place
local STRIDE: number = 0.1 -- Studs the target moves a run, so every viewer always has a record to send

-- Each run's stand-in seconds a clock read moves on, a run's measure being two reads' worth with workers, its own
-- span and its finish's, and the viewers it leaves. The first run hands every turn in and measures 8, so the second
-- hands in 8 x 7 / 8 = 7, leaving the last; it measures 14, so the third may hand in 7 x 7 / 14 = 3 but leaves only
-- 2, a quarter of them, after the one left before; it measures no time, so the fourth hands every turn in again
local SCRIPT: { { step: number, left: { number } } } = {
	{ step = 4, left = {} },
	{ step = 7, left = { 8 } },
	{ step = 0, left = { 6, 7 } },
	{ step = 0, left = {} },
}

return function (): (boolean, string | nil)
	local Wire: any = Environment.load(WIRE)
	local handed: { [number]: { [number]: boolean } } = {} -- Each round's turn viewers handed in, by their index

	-- The stand-in pool with each round's hand-ins read for the turn viewers they carry
	local pool: any = {}
	function pool.new(count: number, name: string, remote: any, settings: any): any
		local built: any = StandIn.new(count, name, remote, settings)
		local send: any = built.send
		local hands: { any } = {}

		built.send = function (self: any, worker: number, round: number, shared: buffer, own: buffer)
			handed[round] = handed[round] or {}
			for index: number = 1, Wire.readOwn(own, hands) do
				local hand: any = hands[index]
				if hand.target == nil then
					handed[round][hand.position.x // SPACING] = true
				end
			end

			send(self, worker, round, shared, own)
		end

		return built
	end

	local Harness: any = Layouts.harness(pool)
	local harness: any = Harness.new(nil, nil, HARNESS_WORKERS)
	local Relay: any = Harness.Relay

	local clients: { any } = {}
	for index: number = 1, VIEWERS do
		local client: any = harness:viewer(`Viewer{index}`)
		client.viewer.position = vector.create(index * SPACING, 0, 0)
		table.insert(clients, client)
	end

	local target: number = harness:spawn("Player", vector.create(0, 0, -60))

	-- Settled with no budget first, so every viewer's turn has a record to send
	harness:runs(2)
	Relay.setBudget(BUDGET)

	for run: number, planned: { step: number, left: { number } } in SCRIPT do
		harness.step = planned.step
		harness.states[target].position += vector.create(run % 2 == 0 and -STRIDE or STRIDE, 0, 0)
		harness:run()

		local round: { [number]: boolean } = handed[#handed] or {}
		local leaving: { [number]: boolean } = {}
		for _, index: number in planned.left do
			leaving[index] = true
		end

		for index: number, client: any in clients do
			local away: boolean = leaving[index] == true
			if (round[index] == true) == away then
				return false, `Run {run} handed viewer {index} in {round[index] == true}, where it is left {away}`
			elseif (#client.seen.sizes > 0) == away then
				return false, `Run {run} sent viewer {index} {#client.seen.sizes} blocks, where it is left {away}`
			end
		end

		if #harness.passed ~= #planned.left then
			return false, `Run {run} passed {#harness.passed} viewers to anti-ESP, not {#planned.left}`
		end
	end

	local left: number, over: number = Relay.caps()
	if left ~= 3 or over ~= 3 then
		return false, `The caps counted {left} viewers left and {over} runs over, not 3 and 3`
	end

	return true, nil
end
