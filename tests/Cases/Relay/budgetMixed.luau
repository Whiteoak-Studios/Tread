--[[
    With some viewers in process and some on a stand-in worker in one run, a
    relay budget of 0 leaves a quarter of each every run, each left viewer
    getting no block that run and none left twice within four runs
--]]

--!strict
local Layouts = require("../../Fixtures/Relay/Layouts")

local EACH: number = 4 -- Viewers in process, and as many on the worker, so each run leaves one of each
local RUNS: number = 16
local EVERY: number = 4 -- No viewer is left in two runs nearer than this
local STRIDE: number = 0.1 -- Studs the target moves a run, so every viewer always has a record to send
local TARGET_AT: vector = vector.create(0, 0, -60)

return function (): (boolean, string | nil)
	local Harness: any = Layouts.harness()
	local harness: any = Harness.new(nil, nil, 1)
	local Relay: any = Harness.Relay
	local target: number = harness:spawn("Player", TARGET_AT)

	-- Views homed where they are first made: the first four in process, the rest on the worker
	local clients: { [any]: any } = {}
	local homes: { [any]: string } = {}
	for row: number, home: string in { "in process", "on the worker" } do
		Relay.useWorkers(home ~= "in process")
		for index: number = 1, EACH do
			local client: any = harness:viewer(`{home} {index}`)
			client.viewer.position = vector.create(index * 10, 0, row * 10)
			clients[client.viewer.key] = client
			homes[client.viewer.key] = home
		end

		harness:run()
	end

	local inProcess: number = Relay.homes()
	if inProcess ~= EACH then
		return false, `{inProcess} views were made in process, not {EACH}`
	end

	Relay.setBudget(0)

	local lastLeft: { [any]: number } = {}
	for run: number = 1, RUNS do
		harness.states[target].position += vector.create(run % 2 == 0 and -STRIDE or STRIDE, 0, 0)
		harness:run()

		local leftOf: { [string]: number } = {}
		for _, call: any in harness.passed do
			local home: string = homes[call.key]
			leftOf[home] = (leftOf[home] or 0) + 1

			local last: number? = lastLeft[call.key]
			if last ~= nil and run - last < EVERY then
				return false, `{call.key.Name} was left on run {last} and again on run {run}`
			elseif #clients[call.key].seen.sizes ~= 0 then
				return false, `{call.key.Name} was left on run {run} and still sent a block`
			end

			lastLeft[call.key] = run
		end

		if leftOf["in process"] ~= 1 or leftOf["on the worker"] ~= 1 then
			return false,
				`Run {run} left {leftOf["in process"]} viewers in process and {leftOf["on the worker"]} on the worker, not 1 each`
		end
	end

	return true, nil
end
