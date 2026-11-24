--[[
    A culled enemy's footsteps from a run the relay budget left a viewer
    reach it on its next turn, a run late and ahead of that run's, alike in
    process and on 2 stand-in workers; none is carried for a viewer that
    took its turn or kept with no budget, and none for an enemy its viewer
    is sent by its next turn
--]]

--!strict
local Environment = require("../../Environment")
local Layouts = require("../../Fixtures/Relay/Layouts")

local HARNESS: string = "tests/Fixtures/Relay/Harness.luau"
local WORKERS: number = 2
local PLAIN_RUNS: number = 4 -- Runs with no budget first
local RUNS: number = 24 -- Then under a budget of 0, where the viewer waits one run in four
local LOOK_FOR: number = 4 -- The most runs the last phase waits for the viewer to be left again
local PACE: number = 5 -- Studs the enemy walks a run, back and forth, past the example's 4.5-stud stride every run
local ENEMY_AT: vector = vector.create(10, 0, 0) -- Inside the example's 40-stud walking earshot of both viewers
local AWAY: vector = vector.create(3000, 0, 0) -- Where the other two viewers stand, past every footstep's range
local MODERATOR_AT: vector = vector.create(3000, 0, 3000)

-- Each footstep a client read this run, as one line
local function heard(client: any): string
	local lines: { string } = {}
	for index: number, step: any in client.seen.footsteps do
		lines[index] = `{step.kind} {step.at.x} {step.at.y} {step.at.z} {step.material.Name}`
	end

	return table.concat(lines, ";")
end

-- Joins two runs' footstep lines as one block lists them, the first run's first
local function join(first: string, second: string): string
	if first == "" then
		return second
	elseif second == "" then
		return first
	end

	return `{first};{second}`
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

-- Runs the runs, giving each run's footsteps of the two viewers as one log, or why the carry went wrong
local function drive(Harness: any, workers: number?): (string?, string?)
	local harness: any = Harness.new(nil, nil, workers)
	local steps: any = Harness.Turn.world.steps

	-- The viewer the budget leaves, and beside it one a moderator watches, so it is never left and hears each run's
	-- steps on time
	local viewer: any = harness:viewer("Viewer")
	local watched: any = harness:viewer("Watched")
	for index: number = 1, 2 do
		harness:viewer(`Other{index}`).viewer.position = AWAY + vector.create(index, 0, 0)
	end

	local moderator: any = harness:viewer("Moderator")
	moderator.viewer.position = MODERATOR_AT
	harness:watch(moderator, watched)

	local enemy: number = harness:spawn("Player", ENEMY_AT)
	harness:hide(viewer, enemy, true)
	harness:hide(watched, enemy, true)

	local log: { string } = {}
	local function walk(run: number)
		harness.states[enemy].position += vector.create(run % 2 == 0 and -PACE or PACE, 0, 0)
	end

	for run: number = 1, PLAIN_RUNS do
		walk(run)
		harness:run()
		if steps.carried ~= 0 then
			return nil, `Run {run}, with no budget, carried {steps.carried} steps`
		elseif heard(viewer) ~= heard(watched) or #watched.seen.footsteps ~= steps.count then
			return nil, `Run {run}, with no budget, gave the viewers {heard(viewer)} and {heard(watched)}`
		end
	end

	Harness.Relay.setBudget(0)

	local before: string = ""
	local wasLeft: boolean = false
	local leftAny: boolean = false
	local carries: number = 0
	for run: number = PLAIN_RUNS + 1, PLAIN_RUNS + RUNS do
		walk(run)

		-- The run before's steps, carried only after a run that left a viewer
		local count: number = 0
		if leftAny then
			count = steps.count
		end

		harness:run()
		leftAny = #harness.passed > 0

		local away: boolean = left(harness, viewer.viewer.key)
		local fresh: string = heard(watched)
		if #watched.seen.footsteps ~= steps.count then
			return nil,
				`Run {run} gave the viewer that turned {#watched.seen.footsteps} steps, not the run's {steps.count}`
		elseif away and #viewer.seen.sizes ~= 0 then
			return nil, `Run {run} sent the viewer it left {#viewer.seen.sizes} blocks`
		elseif not away and wasLeft and heard(viewer) ~= join(before, fresh) then
			return nil, `Run {run} gave the viewer back from a wait {heard(viewer)}, not {join(before, fresh)}`
		elseif not away and not wasLeft and heard(viewer) ~= fresh then
			return nil, `Run {run} gave the viewer {heard(viewer)}, not the run's {fresh}`
		elseif steps.carried ~= count then
			return nil, `Run {run} carried {steps.carried} steps, not the {count} the run before left to carry`
		end

		if wasLeft and not away then
			carries += 1
		end

		table.insert(log, `{away} {heard(viewer)} | {fresh}`)
		before = fresh
		wasLeft = away
	end

	if carries == 0 then
		return nil, "No turn of the viewer came after a run it was left"
	end

	-- An enemy the viewer is sent by its next turn plays its steps from its rig, so none of the wait's is carried
	local run: number = PLAIN_RUNS + RUNS
	for _ = 1, LOOK_FOR do
		if wasLeft then
			break
		end

		run += 1
		walk(run)
		harness:run()
		wasLeft = left(harness, viewer.viewer.key)
	end

	if not wasLeft then
		return nil, `The viewer was not left in {LOOK_FOR} runs`
	end

	harness:hide(viewer, enemy, false)
	run += 1
	walk(run)
	harness:run()

	if Harness.count(viewer.seen.reveals, enemy) ~= 1 then
		return nil, "The enemy shown again was not revealed to the viewer back from its wait"
	elseif #viewer.seen.footsteps ~= 0 then
		return nil, `The viewer back from its wait was carried {heard(viewer)} of an enemy it is now sent`
	elseif #watched.seen.footsteps ~= steps.count then
		return nil, "The viewer still culling the enemy stopped hearing its steps"
	end

	table.insert(log, heard(watched))

	return table.concat(log, "\n"), nil
end

return function (): (boolean, string | nil)
	local serial: string?, why: string? = drive(Environment.load(HARNESS), nil)
	if serial == nil then
		return false, `In process: {why}`
	end

	local onWorkers: string?, failure: string? = drive(Layouts.harness(), WORKERS)
	if onWorkers == nil then
		return false, `On {WORKERS} workers: {failure}`
	elseif onWorkers ~= serial then
		return false, `On {WORKERS} workers the viewers heard other steps than in process`
	end

	return true, nil
end
