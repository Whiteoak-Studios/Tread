--[[
    On a stand-in worker under a relay budget of 0, which every run reaches,
    a dispatched run that handed no worker turn in still leaves the next run
    its quarter of the worker turns
--]]

--!strict
local Layouts = require("../../Fixtures/Relay/Layouts")
local StandIn = require("../../Fixtures/Relay/StandIn")

local SPACING: number = 10 -- Studs between the viewers
local LATER: number = 4 -- Worker viewers that join after the run that handed none in
local QUARTER: number = 1 -- A quarter of those four, rounded down

-- A stand-in pool that counts the rounds it is sent
local function counting(sent: { number }): any
	local pool: any = {}

	function pool.new(count: number, name: string, remote: any, settings: any): any
		local built: any = StandIn.new(count, name, remote, settings)
		local send: any = built.send

		built.send = function (self: any, worker: number, round: number, shared: buffer, own: buffer)
			sent[1] += 1
			send(self, worker, round, shared, own)
		end

		return built
	end

	return pool
end

return function (): (boolean, string | nil)
	local sent: { number } = { 0 }
	local Harness: any = Layouts.harness(counting(sent))
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

	Relay.setBudget(0)
	local before: number = sent[1]
	harness:run()

	if sent[1] ~= before + 1 then
		return false, `The run with only the moderator on the worker sent {sent[1] - before} rounds, not 1`
	elseif #harness.passed ~= 0 then
		return false, `The run with no worker turn left {#harness.passed} viewers, not 0`
	end

	for index: number = 1, LATER do
		harness:viewer(`Later{index}`).viewer.position = vector.create(index * SPACING, 0, SPACING * 2)
	end

	harness:run()
	if #harness.passed ~= QUARTER then
		return false,
			`At a budget of 0 the run after one that handed no worker turn in left {#harness.passed} viewers, not {QUARTER}`
	end

	return true, nil
end
