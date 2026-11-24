--[[
    A viewer the relay budget left in one run, absent from the list in the
    next and back in the one after, takes that turn as any other: one run's
    credit, none of the steps carried that run, and turns the budget forces
--]]

--!strict
local Environment = require("../../Environment")

local HARNESS: string = "tests/Fixtures/Relay/Harness.luau"
local PLAIN_RUNS: number = 2 -- Runs with no budget first, past the reveals
local LOOK_FOR: number = 6 -- The most runs a budget of 0 takes to leave the viewer, one of four free viewers a run
local FORCED: number = 2 -- The turns back from the absence the budget forces, the rest of its one run in four
local OTHERS: number = 3 -- So the run it is absent from still has four turn viewers, and leaves one
local PACE: number = 5 -- Studs the enemy walks a run, back and forth, past the example's 4.5-stud stride every run
local NPC_STRIDE: number = 0.1 -- Studs the NPC moves a run, back and forth, so it always has a change to send
local ENEMY_AT: vector = vector.create(10, 0, 0) -- Inside the example's 40-stud walking earshot of both viewers
local NPC_AT: vector = vector.create(0, 0, -300) -- Past npcs.near, where it goes at the example's farRate
local AWAY: vector = vector.create(3000, 0, 0) -- Where the other viewers stand, past every footstep's range
local MODERATOR_AT: vector = vector.create(3000, 0, 3000)
local ONE_RUN: number = 2 / 20 -- The credit one run adds the NPC, its 2 Hz farRate over the 20 Hz relay
local SLACK: number = 1e-6 -- A credit's f32 rounding

-- Each footstep a client read this run, as one line
local function heard(client: any): string
	local lines: { string } = {}
	for index: number, step: any in client.seen.footsteps do
		lines[index] = `{step.kind} {step.at.x} {step.at.y} {step.at.z} {step.material.Name}`
	end

	return table.concat(lines, ";")
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

return function (): (boolean, string | nil)
	local Harness: any = Environment.load(HARNESS)
	local harness: any = Harness.new()
	local Turn: any = Harness.Turn
	local steps: any = Turn.world.steps

	-- The viewer the budget leaves, and beside it one a moderator watches, so it is never left and hears each run's
	-- steps on time
	local viewer: any = harness:viewer("Viewer")
	local watched: any = harness:viewer("Watched")
	for index: number = 1, OTHERS do
		harness:viewer(`Other{index}`).viewer.position = AWAY + vector.create(index, 0, 0)
	end

	local moderator: any = harness:viewer("Moderator")
	moderator.viewer.position = MODERATOR_AT
	harness:watch(moderator, watched)

	local enemy: number = harness:spawn("Player", ENEMY_AT)
	harness:hide(viewer, enemy, true)
	harness:hide(watched, enemy, true)
	local npc: number = harness:spawn("Npc", NPC_AT)

	local function credit(): number
		return buffer.readf32(Turn.view(viewer.viewer.key).aim, npc * 4)
	end

	local run: number = 0
	local function walk()
		run += 1
		local sign: number = run % 2 == 0 and -1 or 1
		harness.states[enemy].position += vector.create(sign * PACE, 0, 0)
		harness.states[npc].position += vector.create(sign * NPC_STRIDE, 0, 0)
		harness:run()
	end

	for _ = 1, PLAIN_RUNS do
		walk()
	end

	-- The NPC's credit as the viewer's last turn before the run that left it stored it
	Harness.Relay.setBudget(0)
	local before: number = credit()
	local found: boolean = false
	for _ = 1, LOOK_FOR do
		walk()
		if left(harness, viewer.viewer.key) then
			found = true

			break
		end

		before = credit()
	end

	if not found then
		return false, `The budget did not leave the viewer in {LOOK_FOR} runs`
	end

	-- Absent the next run, which still leaves another viewer and so carries the steps of the run it left
	local at: number = table.find(harness.viewers, viewer.viewer) :: number
	table.remove(harness.viewers, at)
	walk()

	if #harness.passed ~= 1 then
		return false, `The run the viewer was absent from left {#harness.passed} viewers, not 1`
	end

	table.insert(harness.viewers, at, viewer.viewer)
	walk()

	local added: number = credit() - before + Harness.count(viewer.seen.records, npc)
	if left(harness, viewer.viewer.key) then
		return false, "The viewer back from its absence was left again at once"
	elseif steps.carried == 0 then
		return false, "The run the viewer came back in carried no steps of the run before"
	elseif #watched.seen.footsteps == 0 then
		return false, "The viewer that turned heard none of the run's steps"
	elseif heard(viewer) ~= heard(watched) then
		return false, `The viewer back from its absence heard {heard(viewer)}, not the run's {heard(watched)}`
	elseif math.abs(added - ONE_RUN) > SLACK then
		return false, `The viewer back from its absence took {added} of the NPC's credit, not one run's {ONE_RUN}`
	end

	for turn: number = 2, FORCED do
		walk()
		if left(harness, viewer.viewer.key) then
			return false, `The budget left the viewer on its turn {turn} back, inside its one run in four`
		end
	end

	return true, nil
end
