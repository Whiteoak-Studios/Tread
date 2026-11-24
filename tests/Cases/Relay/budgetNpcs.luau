--[[
    A near NPC's records wait with a left viewer's turn: none on the run the
    relay budget leaves it, one on its next turn, so 3 in 4 runs, 15 Hz, at
    worst, where a viewer never left gets one every relay tick
--]]

--!strict
local Environment = require("../../Environment")

local HARNESS: string = "tests/Fixtures/Relay/Harness.luau"
local FROM: number = 3 -- The first run counted, past the reveal
local RUNS: number = 42 -- The last, 40 runs on, the viewer waiting on ten of them
local STRIDE: number = 0.1 -- Studs the NPC moves a run, back and forth, so it always has a change to send
local NPC_AT: vector = vector.create(0, 0, -100) -- Inside the example's 197-stud npcs.near, so due every relay tick
local AWAY: vector = vector.create(3000, 0, 0)
local MODERATOR_AT: vector = vector.create(3000, 0, 3000)
local STEADY: number = 40 -- The never-left viewer's records over the counted runs, one a run
local LATE: number = 30 -- The left viewer's, one on each of the 30 runs it takes

return function (): (boolean, string | nil)
	local Harness: any = Environment.load(HARNESS)
	local harness: any = Harness.new()

	for index: number = 1, 2 do
		harness:viewer(`Other{index}`).viewer.position = AWAY + vector.create(index, 0, 0)
	end

	-- The viewer the budget leaves, and one a moderator watches, so it is never left
	local viewer: any = harness:viewer("Viewer")
	local steady: any = harness:viewer("Steady")
	local moderator: any = harness:viewer("Moderator")
	moderator.viewer.position = MODERATOR_AT
	harness:watch(moderator, steady)

	local npc: number = harness:spawn("Npc", NPC_AT)
	Harness.Relay.setBudget(0)

	local late: number, onTime: number, waits: number = 0, 0, 0
	for run: number = 1, RUNS do
		harness.states[npc].position += vector.create(run % 2 == 0 and -STRIDE or STRIDE, 0, 0)
		harness:run()

		local waited: boolean = false
		for _, call: any in harness.passed do
			waited = waited or call.key == viewer.viewer.key
		end

		local got: number = Harness.count(viewer.seen.records, npc)
		local due: number = Harness.count(steady.seen.records, npc)
		if run >= FROM then
			if due ~= 1 then
				return false, `The viewer never left got {due} records of the NPC on run {run}, not 1`
			elseif got ~= (waited and 0 or 1) then
				return false, `The viewer got {got} records of the NPC on run {run}, where it was left {waited}`
			end

			late += got
			onTime += due
			if waited then
				waits += 1
			end
		end
	end

	if onTime ~= STEADY or late ~= LATE then
		return false,
			`Over the counted runs the NPC sent {onTime} and {late} records, with {waits} waits, not {STEADY} and {LATE}`
	end

	return true, nil
end
