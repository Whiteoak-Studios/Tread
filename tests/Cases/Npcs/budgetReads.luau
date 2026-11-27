--[[
    A budgeted walk reads the clock once as it begins, then once for each
    NPC not forced it reaches until the budget is spent, and never for one
    stepping forced or for any it reaches after the budget is spent
--]]

--!strict
local Environment = require("../../Environment")

local STAGE: string = "tests/Fixtures/Npcs/Stage.luau"
local STEP: number = 1 -- Seconds the stand-in clock moves on at each read
local TWO: number = 2.5 -- Spent at a walk's fourth read, so two NPCs not forced step a tick
local COUNT: number = 4
local SPACING: number = 10 -- Studs between the NPCs along Z

type Tick = {
	reads: number, -- The clock's reads that tick
	waits: string, -- The slots that waited, in slot order
}

-- Each tick from the cursor at slot 0, worked out from the walk's rules
local TICKS: { Tick } = {
	{ reads = 4, waits = "2 3" }, -- The walk's start, slots 0 and 1 stepping and slot 2 finding the budget spent
	{ reads = 3, waits = "" }, -- The start, then slots 2 and 3 stepping forced unread, then slots 0 and 1
	{ reads = 4, waits = "0 1" }, -- The start, slots 2 and 3 stepping and slot 0 finding it spent, slot 1 unread
}

return function (): (boolean, string | nil)
	local stage: any = Environment.load(STAGE)
	local clock: any = stage.clock(STEP)
	stage.start(clock.read)

	local npcs: { any } = {}
	for index: number = 1, COUNT do
		table.insert(npcs, stage.Npcs.create(vector.create(-20, stage.resting, (index - 2) * SPACING), 0))
	end

	stage.Npcs.setBudget(TWO)

	for tick: number, expected: Tick in TICKS do
		local before: number = clock.reads
		stage.Npcs.step(tick)

		local slots: { string } = {}
		for _, npc: any in npcs do
			if npc:getState().tick ~= tick then
				table.insert(slots, `{npc.slot}`)
			end
		end

		local waits: string = table.concat(slots, " ")
		if waits ~= expected.waits then
			return false, `On tick {tick} the NPCs in slots "{waits}" waited, not "{expected.waits}"`
		elseif clock.reads - before ~= expected.reads then
			return false, `Tick {tick}'s walk read the clock {clock.reads - before} times, not {expected.reads}`
		end
	end

	return true, nil
end
