--[[
    Under a relay budget a left viewer's next turn judges a staff member's
    steps of the run it was left by that run's Invisible mark, in process
    and on a stand-in worker: one taken off while that run's round is out,
    one set and taken off again before the next run, and one set after it
--]]

--!strict
local Environment = require("../../Environment")
local Layouts = require("../../Fixtures/Relay/Layouts")
local StandIn = require("../../Fixtures/Relay/StandIn")

local WIRE: string = "src/Server/Relay/Wire.luau"
local PLAIN_RUNS: number = 2 -- Runs with no budget first, past the reveals, so every run under it has steps
local LOOK_FOR: number = 6 -- The most runs a budget of 0 takes to leave the viewer, one of its three free viewers a run
local PACE: number = 5 -- Studs each body walks a run, back and forth, past the example's 4.5-stud stride every run
local START_X: number = 10
local VIEWER_AT: vector = vector.create(-1, 0, 0) -- Each at a place of its own, which a worker's hand-in names
local FRESH_AT: vector = vector.create(1, 0, 0)
local AWAY: vector = vector.create(3000, 0, 0) -- Where the other two viewers stand, past every footstep's range
local FAR_AT: vector = vector.create(-3000, 0, 0) -- A viewer alone on the worker, so a run with views in process sends a round
local MODERATOR_AT: vector = vector.create(3000, 0, 3000)

-- Each body's lane, the z its steps fall on, inside the example's 40-stud walking earshot of both viewers: an enemy
-- and the staff member, both hidden from the two by anti-ESP throughout
local LANES: { [string]: number } = { enemy = 2, staff = 4 }

-- What happens to the staff member's mark: Invisible until the run the viewer is left, taken off while that run's round
-- is out; or not Invisible, then set and taken off again between that run and the next; or set only between them
type Scenario = "out" | "twice" | "after"
type Home = "process" | "worker"

-- The places of the turn viewers the round being sent hands in, and what to do as its worker takes it
type State = { handed: { vector }, during: (() -> ())? }

-- A footstep's lane, from the z it fell on
local function laneOf(step: any): string
	local z: number = math.round(step.at.z)
	for name: string, lane: number in LANES do
		if lane == z then
			return name
		end
	end

	error(`A footstep fell at z {step.at.z}, on no body's lane`)
end

-- The footsteps a client read this run, each as one line, those of the lane given left out
local function heard(client: any, without: string?): { string }
	local lines: { string } = {}
	for _, step: any in client.seen.footsteps do
		if laneOf(step) ~= without then
			table.insert(lines, `{step.kind} {step.at.x} {step.at.y} {step.at.z} {step.material.Name}`)
		end
	end

	return lines
end

-- How many of the footsteps a client read this run fell on a lane
local function onLane(client: any, name: string): number
	local count: number = 0
	for _, step: any in client.seen.footsteps do
		if laneOf(step) == name then
			count += 1
		end
	end

	return count
end

-- Whether a run passed a key's viewer to anti-ESP, which is how the case knows the budget left it
local function left(harness: any, key: any): boolean
	for _, call: any in harness.passed do
		if call.key == key then
			return true
		end
	end

	return false
end

--[[
    A stand-in pool that keeps the places of the turn viewers each round
    hands in, and runs the state's during, once, as the round is delivered,
    while the round is still out
--]]

local function pooled(state: State): any
	local Wire: any = Environment.load(WIRE)
	local pool: any = {}

	function pool.new(count: number, name: string, remote: any, settings: any): any
		local built: any = StandIn.new(count, name, remote, settings)
		local send: any = built.send
		local deliver: any = built.deliver
		local hands: { any } = {}

		built.send = function (self: any, worker: number, round: number, shared: buffer, own: buffer)
			table.clear(state.handed)
			for index: number = 1, Wire.readOwn(own, hands) do
				if hands[index].target == nil then
					table.insert(state.handed, hands[index].position)
				end
			end

			send(self, worker, round, shared, own)
		end

		built.deliver = function (self: any)
			local during: (() -> ())? = state.during
			state.during = nil
			if during then
				during()
			end

			deliver(self)
		end

		return built
	end

	return pool
end

-- Runs one scenario with the viewers' views where home puts them, giving why the turn after the wait heard otherwise
local function drive(scenario: Scenario, home: Home): string?
	local state: State = { handed = {}, during = nil }
	local Harness: any = Layouts.harness(pooled(state))
	local harness: any = Harness.new(nil, nil, 1)
	local Relay: any = Harness.Relay
	local steps: any = Harness.Turn.world.steps

	if home == "process" then
		Relay.useWorkers(false)
	end

	-- The viewer the budget leaves, and beside it one a moderator watches, so it is never left and hears each run's
	-- steps as a fresh turn does
	local viewer: any = harness:viewer("Viewer")
	viewer.viewer.position = VIEWER_AT
	local fresh: any = harness:viewer("Fresh")
	fresh.viewer.position = FRESH_AT
	for index: number = 1, 2 do
		harness:viewer(`Other{index}`).viewer.position = AWAY + vector.create(index, 0, 0)
	end

	local moderator: any = harness:viewer("Moderator")
	moderator.viewer.position = MODERATOR_AT
	harness:watch(moderator, fresh)

	local slots: { [string]: number } = {}
	for name: string, lane: number in LANES do
		slots[name] = harness:spawn("Player", vector.create(START_X, 0, lane))
		harness:hide(viewer, slots[name], true)
		harness:hide(fresh, slots[name], true)
	end

	local staff: number = slots.staff
	if scenario == "out" then
		Relay.setInvisible(staff, true)
	end

	local run: number = 0
	local function walk()
		run += 1
		local pace: number = run % 2 == 0 and -PACE or PACE
		for _, slot: number in slots do
			harness.states[slot].position += vector.create(pace, 0, 0)
		end

		harness:run()
	end

	-- The first run homes every view, in process for that home and on the worker otherwise
	walk()
	if home == "process" then
		Relay.useWorkers(true)
		harness:viewer("Far").viewer.position = FAR_AT
	end

	for _ = 2, PLAIN_RUNS do
		walk()
	end

	-- Whether the round being delivered left the viewer: in process its pass came in the run, and on the worker its hand
	-- went to no round
	local function leftNow(): boolean
		if home == "process" then
			return left(harness, viewer.viewer.key)
		end

		return not table.find(state.handed, viewer.viewer.position)
	end

	Relay.setBudget(0)
	local out: boolean = false
	local found: boolean = false
	for _ = 1, LOOK_FOR do
		if scenario == "out" then
			state.during = function ()
				if leftNow() then
					out = not Relay.finish()
					Relay.setInvisible(staff, false)
				end
			end
		end

		walk()
		if left(harness, viewer.viewer.key) then
			found = true

			break
		end
	end

	if not found then
		return `The budget did not leave the viewer in {LOOK_FOR} runs`
	elseif scenario == "out" and not out then
		return "The staff member's mark came off with no round out"
	end

	local stepped: boolean = false
	for index: number = 0, steps.count - 1 do
		if buffer.readu16(steps.slots, index * 2) == staff then
			stepped = true
		end
	end

	if not stepped then
		return "The staff member made no step in the run the viewer was left"
	end

	-- A step of a staff member Invisible at the viewer's next turn is heard by no one then, though it fell while visible
	local before: { string } = heard(fresh, scenario == "after" and "staff" or nil)
	local staffMeant: number = scenario == "after" and 0 or onLane(fresh, "staff")

	if scenario == "twice" then
		Relay.setInvisible(staff, true)
		Relay.setInvisible(staff, false)
	elseif scenario == "after" then
		Relay.setInvisible(staff, true)
	end

	walk()

	local expected: { string } = table.move(heard(fresh), 1, #fresh.seen.footsteps, #before + 1, before)
	local staffHeard: number = onLane(viewer, "staff")
	staffMeant += onLane(fresh, "staff")

	if left(harness, viewer.viewer.key) then
		return "The viewer was left again the run after its wait"
	elseif steps.carried == 0 then
		return "The turn after the wait carried no step of the run before"
	elseif staffHeard ~= staffMeant then
		return `The turn after the wait heard {staffHeard} of the staff member's steps, not {staffMeant}`
	elseif table.concat(heard(viewer), ";") ~= table.concat(expected, ";") then
		return `The turn after the wait heard {table.concat(heard(viewer), ";")}, not {table.concat(expected, ";")}`
	end

	return nil
end

return function (): (boolean, string | nil)
	for _, scenario: Scenario in { "out", "twice", "after" } :: { Scenario } do
		for _, home: Home in { "process", "worker" } :: { Home } do
			local why: string? = drive(scenario, home)
			if why then
				return false, `{scenario}, {home}: {why}`
			end
		end
	end

	return true, nil
end
