--[[
    A staff member Invisible in the run the relay budget left a viewer is
    never heard from that run: the viewer's next turn carries none of its
    steps and hears its new ones as a viewer that turned does, in process
    and on 2 stand-in workers. Nor is a step of that run carried for a body
    then Parked, one that has slept, died or whose slot a new life took
--]]

--!strict
local Environment = require("../../Environment")
local Layouts = require("../../Fixtures/Relay/Layouts")

local HARNESS: string = "tests/Fixtures/Relay/Harness.luau"
local WORKERS: number = 2
local PLAIN_RUNS: number = 2 -- Runs with no budget first, past the reveals, so every run under it has steps
local LOOK_FOR: number = 6 -- The most runs a budget of 0 takes to leave the viewer, one of its three free viewers a run
local COUNTERS: number = 4 -- The values a state's land counter wraps through, 2 ^ Constants.COUNTER_BITS
local PACE: number = 5 -- Studs each walker walks a run, back and forth, past the example's 4.5-stud stride every run
local START_X: number = 10
local AWAY: vector = vector.create(3000, 0, 0) -- Where the other two viewers stand, past every footstep's range
local MODERATOR_AT: vector = vector.create(3000, 0, 3000)

-- Each body's lane, the z its steps fall on, all inside the example's 40-stud walking earshot of both viewers at the
-- origin: a culled enemy, the staff member, a body Parked through the run the viewer is left, one that sleeps after it,
-- one that dies after it, and one whose slot a new life takes after it
local LANES: { [string]: number } = { enemy = 2, staff = 4, parked = 6, sleeper = 8, dying = 10, reborn = 12 }

-- The bodies anti-ESP hides from both viewers throughout; it shows them the sleeper and the reborn body until after the
-- run the viewer is left
local CULLED: { string } = { "enemy", "staff", "parked", "dying" }

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

-- Gives a released slot a new life by taking every slot freed before it, then frees those again
local function reborn(Slots: any, slot: number)
	local taken: { number } = {}
	while true do
		local free: number = Slots.take("Player")
		if free == slot then
			break
		end

		table.insert(taken, free)
	end

	Slots.setEntry(slot, { kind = "Player", rig = "A" })
	for _, other: number in taken do
		Slots.release(other)
	end
end

-- Runs the case on a harness, giving why the turn after the viewer's wait heard otherwise, or nil
local function drive(Harness: any, workers: number?): string?
	local harness: any = Harness.new(nil, nil, workers)
	local Relay: any = Harness.Relay
	local Slots: any = Harness.Slots
	local steps: any = Harness.Turn.world.steps

	-- The viewer the budget leaves, and beside it one a moderator watches, so it is never left and hears each run's
	-- steps as a fresh turn does
	local viewer: any = harness:viewer("Viewer")
	local fresh: any = harness:viewer("Fresh")
	for index: number = 1, 2 do
		harness:viewer(`Other{index}`).viewer.position = AWAY + vector.create(index, 0, 0)
	end

	local moderator: any = harness:viewer("Moderator")
	moderator.viewer.position = MODERATOR_AT
	harness:watch(moderator, fresh)

	local slots: { [string]: number } = {}
	for name: string, lane: number in LANES do
		slots[name] = harness:spawn("Player", vector.create(START_X, 0, lane))
	end

	for _, name: string in CULLED do
		harness:hide(viewer, slots[name], true)
		harness:hide(fresh, slots[name], true)
	end

	-- Invisible and Parked as the server handle sets them, the Parked body landing once a run so it has steps to judge
	Relay.setInvisible(slots.staff, true)
	harness.states[slots.parked].moveMode = "Parked"
	Relay.setInvisible(slots.parked, true)

	local run: number = 0
	local function walk()
		run += 1
		local pace: number = run % 2 == 0 and -PACE or PACE
		for name: string, slot: number in slots do
			local state: any = harness.states[slot]
			if name == "parked" then
				state.lands = (state.lands + 1) % COUNTERS
			elseif state then
				state.position += vector.create(pace, 0, 0)
			end
		end

		harness:run()
	end

	for _ = 1, PLAIN_RUNS do
		walk()
	end

	Relay.setBudget(0)
	local found: boolean = false
	for _ = 1, LOOK_FOR do
		walk()
		if left(harness, viewer.viewer.key) then
			found = true

			break
		end
	end

	if not found then
		return `The budget did not leave the viewer in {LOOK_FOR} runs`
	end

	-- Every body stepped in the run the viewer was left, so each has steps the next turn could carry
	local stepped: { [number]: number } = {}
	for index: number = 0, steps.count - 1 do
		local slot: number = buffer.readu16(steps.slots, index * 2)
		stepped[slot] = (stepped[slot] or 0) + 1
	end

	for name: string, slot: number in slots do
		if stepped[slot] == nil then
			return `The {name} body made no step in the run the viewer was left`
		end
	end

	-- What the fresh viewer heard that run is what the waiting viewer would have, the dying body's steps among them
	local before: { string } = heard(fresh, "dying")
	if onLane(fresh, "staff") + onLane(fresh, "parked") ~= 0 then
		return "The fresh viewer heard the Invisible staff member or the Parked body"
	end

	-- Then the staff member shows itself, the Parked body walks again, one body sleeps where it stood with its lying
	-- body hidden, one dies, and the last one's slot goes to a new life that is hidden
	Relay.setInvisible(slots.staff, false)
	harness.states[slots.parked].moveMode = "Walk"
	Relay.setInvisible(slots.parked, false)

	Slots.setEntry(slots.sleeper, { kind = "Sleeper", rig = "A" })
	harness:despawn(slots.dying)

	local kept: any = harness.states[slots.reborn]
	harness:despawn(slots.reborn)
	reborn(Slots, slots.reborn)
	harness.states[slots.reborn] = kept

	for _, name: string in { "sleeper", "reborn" } do
		harness:hide(viewer, slots[name], true)
		harness:hide(fresh, slots[name], true)
	end

	-- The parked body stops landing and the dead one is gone
	local parked: number = slots.parked
	slots.parked = nil
	slots.dying = nil
	walk()
	slots.parked = parked

	if left(harness, viewer.viewer.key) then
		return "The viewer was left again the run after its wait"
	elseif steps.carried == 0 then
		return "The turn after the wait carried no step of the run before"
	elseif onLane(fresh, "staff") == 0 then
		return "The fresh viewer did not hear the staff member once it showed itself"
	end

	local staff: number, fresher: number = onLane(viewer, "staff"), onLane(fresh, "staff")
	if staff ~= fresher then
		return `The turn after the wait heard {staff} of the staff member's steps, not the run's {fresher}`
	end

	for _, name: string in { "parked", "sleeper", "dying", "reborn" } do
		if onLane(viewer, name) ~= 0 then
			return `The turn after the wait heard {onLane(viewer, name)} steps of the {name} body from the run before`
		end
	end

	local expected: { string } = table.move(heard(fresh), 1, #fresh.seen.footsteps, #before + 1, before)
	if table.concat(heard(viewer), ";") ~= table.concat(expected, ";") then
		return `The turn after the wait heard {table.concat(heard(viewer), ";")}, not {table.concat(expected, ";")}`
	end

	return nil
end

return function (): (boolean, string | nil)
	local why: string? = drive(Environment.load(HARNESS), nil)
	if why then
		return false, `In process: {why}`
	end

	why = drive(Layouts.harness(), WORKERS)
	if why then
		return false, `On {WORKERS} workers: {why}`
	end

	return true, nil
end
