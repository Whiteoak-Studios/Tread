--[[
    A turn after a run the relay budget left its viewer, with hard room for
    fewer steps than the two runs': the carried go first in the order they
    fell and the run's own give way, in blocks inside 896 B and 255 entries,
    in process and on 2 stand-in workers
--]]

--!strict
local Environment = require("../../Environment")
local Layouts = require("../../Fixtures/Relay/Layouts")

local HARNESS: string = "tests/Fixtures/Relay/Harness.luau"
local BLOCK: string = "src/Codec/Block.luau"
local WORKERS: number = 2
local PLAIN_RUNS: number = 2 -- Runs with no budget first, so every run under it has steps of the run before
local LOOK_FOR: number = 6 -- The most runs a budget of 0 takes to leave the viewer, one of four free viewers a run
local SIDE: number = 10 -- Enemies along each side of the square they stand in, 2 studs apart, 100 in all
local SPACING: number = 2
local ENEMIES: number = SIDE * SIDE
local PACE: number = 4.5 -- Studs each walks a run, back and forth, the example's walking stride, so one step a run
local OTHERS: number = 3 -- The other viewers, so a run leaves one of four
local AWAY: vector = vector.create(3000, 0, 0) -- Where they stand, past every footstep's range
local HARD: number = 96000 -- The example's hard budget in bytes a second, which the traffic leaves ROOM of
local ROOM: number = 1524 -- Two blocks' 9 B header and 3 B framing, 24 B, and 150 steps of 10 B, the 151st refused
local HEARD: number = 150
local SIZES: string = "889 629" -- 88 steps after the first block's header, at most 896 B, and the other 62 after the second's
local MAX_BLOCK: number = 896 -- Constants.MAX_RELAY_BYTES
local MAX_ENTRIES: number = 255 -- A block's u8 count
local HEADER: number = 9 -- Constants.RELAY_HEADER_BYTES
local FOOTSTEP_BYTES: number = 10 -- Constants.FOOTSTEP_BYTES

-- A footstep as one line
local function line(step: any): string
	return `{step.kind} {step.at.x} {step.at.y} {step.at.z} {step.material.Name}`
end

-- Each footstep a client read this run, as one line
local function heard(client: any): { string }
	local lines: { string } = {}
	for index: number, step: any in client.seen.footsteps do
		lines[index] = line(step)
	end

	return lines
end

-- The count entries of the run's steps from first, as lines, onto lines
local function entries(Block: any, steps: any, first: number, count: number, lines: { string })
	for index: number = first, first + count - 1 do
		local step: any = {}
		Block.readFootstep(steps.data, index * FOOTSTEP_BYTES, step)
		table.insert(lines, line(step))
	end
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

-- Why the turn after the viewer's wait placed its steps otherwise, or nil
local function drive(Harness: any, workers: number?): string?
	local harness: any = Harness.new(nil, nil, workers)
	local Block: any = Environment.load(BLOCK)
	local steps: any = Harness.Turn.world.steps

	local viewer: any = harness:viewer("Viewer")
	for index: number = 1, OTHERS do
		harness:viewer(`Other{index}`).viewer.position = AWAY + vector.create(index, 0, 0)
	end

	local enemies: { number } = {}
	for row: number = 1, SIDE do
		for column: number = 1, SIDE do
			local at: vector = vector.create((column - SIDE / 2) * SPACING, 0, (row - SIDE / 2) * SPACING)
			local enemy: number = harness:spawn("Player", at)
			harness:hide(viewer, enemy, true)
			table.insert(enemies, enemy)
		end
	end

	harness.traffic = HARD - ROOM

	local wasLeft: boolean = false
	for run: number = 1, PLAIN_RUNS + LOOK_FOR do
		if run == PLAIN_RUNS + 1 then
			Harness.Relay.setBudget(0)
		end

		local pace: number = run % 2 == 0 and -PACE or PACE
		for _, enemy: number in enemies do
			harness.states[enemy].position += vector.create(pace, 0, 0)
		end

		harness:run()

		if wasLeft then
			if steps.count ~= ENEMIES or steps.carried ~= ENEMIES then
				return `The turn after the wait had {steps.carried} steps carried and {steps.count} its own, not {ENEMIES} each`
			end

			local expected: { string } = {}
			entries(Block, steps, steps.count, steps.carried, expected)
			entries(Block, steps, 0, steps.count, expected)
			for index: number = #expected, HEARD + 1, -1 do
				expected[index] = nil
			end

			local sizes: { string } = {}
			for _, size: number in viewer.seen.sizes do
				if size > MAX_BLOCK or (size - HEADER) // FOOTSTEP_BYTES > MAX_ENTRIES then
					return `The turn after the wait sent a block of {size} B`
				end

				table.insert(sizes, `{size}`)
			end

			if table.concat(sizes, " ") ~= SIZES then
				return `The turn after the wait sent blocks of {table.concat(sizes, " ")} B, not {SIZES}`
			elseif table.concat(heard(viewer), ";") ~= table.concat(expected, ";") then
				return `The turn after the wait heard {#viewer.seen.footsteps} steps other than the {HEARD} carried first`
			end

			return nil
		end

		wasLeft = run > PLAIN_RUNS and left(harness, viewer.viewer.key)
	end

	return `The budget did not leave the viewer in {LOOK_FOR} runs`
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
