--[[
    A worker viewer the relay budget left in a run its stand-in worker threw
    in after reading its looks and before filing its bodies hears none of
    the older steps the worker still holds on its next turn, only that run's
--]]

--!strict
local Environment = require("../../Environment")
local Layouts = require("../../Fixtures/Relay/Layouts")
local StandIn = require("../../Fixtures/Relay/StandIn")

local WIRE: string = "src/Server/Relay/Wire.luau"
local PLAIN_RUNS: number = 3 -- Runs with no budget first, so the worker holds steps of the run before every run
local PACE: number = 5 -- Studs the enemy walks a run, back and forth, past the example's 4.5-stud stride every run
local ENEMY_AT: vector = vector.create(10, 0, 0) -- Inside the example's 40-stud walking earshot of every viewer
local MODERATOR_AT: vector = vector.create(3000, 0, 3000)
local FIRST_CALL: number = 7 -- The first queued call's kind in an own hand-in, after its 7 B header
local NO_KIND: number = 9 -- A call kind a worker refuses, past its five
local REFUSED: string = "queued call is of kind" -- What the worker's refusal says

-- The viewers the budget may leave, each at a place of its own its hand-in names, and the one a moderator watches, so it
-- is never left and hears each run's steps on time
local PLACES: { vector } = { vector.create(-5, 0, 0), vector.create(0, 0, 5), vector.create(0, 0, -5) }
local WATCHED_AT: vector = vector.create(5, 0, 0)

-- Each footstep a client read this run, as one line
local function heard(client: any): string
	local lines: { string } = {}
	for index: number, step: any in client.seen.footsteps do
		lines[index] = `{step.kind} {step.at.x} {step.at.y} {step.at.z} {step.material.Name}`
	end

	return table.concat(lines, ";")
end

--[[
    A stand-in pool that keeps the places of the turn viewers each round
    hands in, and while spoil is set hands its worker a copy of the own
    hand-in whose first call has a kind none is, so its run throws there
--]]

local function spoiling(state: { spoil: boolean, handed: { vector } }): any
	local Wire: any = Environment.load(WIRE)
	local pool: any = {}

	function pool.new(count: number, name: string, remote: any, settings: any): any
		local built: any = StandIn.new(count, name, remote, settings)
		local send: any = built.send
		local hands: { any } = {}

		built.send = function (self: any, worker: number, round: number, shared: buffer, own: buffer)
			table.clear(state.handed)
			for index: number = 1, Wire.readOwn(own, hands) do
				if hands[index].target == nil then
					table.insert(state.handed, hands[index].position)
				end
			end

			if state.spoil then
				local spoiled: buffer = buffer.create(buffer.len(own))
				buffer.copy(spoiled, 0, own)
				buffer.writeu8(spoiled, FIRST_CALL, NO_KIND)
				own = spoiled
			end

			send(self, worker, round, shared, own)
		end

		return built
	end

	return pool
end

return function (): (boolean, string | nil)
	local state: { spoil: boolean, handed: { vector } } = { spoil = false, handed = {} }
	local Harness: any = Layouts.harness(spoiling(state))
	local harness: any = Harness.new(nil, nil, 1)
	local Relay: any = Harness.Relay

	local clients: { any } = {}
	for index: number, at: vector in PLACES do
		local client: any = harness:viewer(`Viewer{index}`)
		client.viewer.position = at
		clients[index] = client
	end

	local watched: any = harness:viewer("Watched")
	watched.viewer.position = WATCHED_AT
	local moderator: any = harness:viewer("Moderator")
	moderator.viewer.position = MODERATOR_AT
	harness:watch(moderator, watched)

	local enemy: number = harness:spawn("Player", ENEMY_AT)
	harness:hide(watched, enemy, true)
	for _, client: any in clients do
		harness:hide(client, enemy, true)
	end

	local function walk(run: number)
		harness.states[enemy].position += vector.create(run % 2 == 0 and -PACE or PACE, 0, 0)
	end

	for run: number = 1, PLAIN_RUNS do
		walk(run)
		harness:run()
	end

	-- The first run under the budget leaves one viewer, and the call queued for the worker before it throws there
	Relay.setBudget(0)
	Relay.shotNear(watched.viewer.key, enemy)
	local run: number = PLAIN_RUNS + 1
	walk(run)
	state.spoil = true
	harness.passed = {}
	harness.tick += 1
	Relay.run(harness.tick, harness.viewers, harness.states, harness.commands, harness.platforms)
	harness.pool:deliver()
	state.spoil = false

	local finished: boolean, failure: unknown = pcall(Relay.finish)
	if finished or not string.find(tostring(failure), REFUSED, 1, true) then
		return false, `The run its worker threw in finished {finished}: {failure}`
	end

	local away: any = nil
	for _, client: any in clients do
		if not table.find(state.handed, client.viewer.position) then
			if away ~= nil then
				return false, "The run under the budget left more than one of the four turn viewers"
			end

			away = client
		end
	end

	if away == nil then
		return false, "The run under the budget handed every viewer in"
	end

	run += 1
	walk(run)
	harness:run()

	if not table.find(state.handed, away.viewer.position) then
		return false, "The viewer left in the run its worker threw in was left again the run after"
	elseif #watched.seen.footsteps == 0 then
		return false, "The viewer that turned heard none of the run's steps"
	elseif heard(away) ~= heard(watched) then
		return false,
			`The viewer whose worker threw in the run it was left heard {heard(away)}, not the run's {heard(watched)}`
	end

	return true, nil
end
