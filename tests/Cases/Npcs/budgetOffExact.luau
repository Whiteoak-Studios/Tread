--[[
    With no budget every NPC steps every tick with no clock read, a part
    moved into a still one frees it on its next tenth tick alone, and no
    check is owed after; a budget cleared drops the checks its waits owed
--]]

--!strict
local Environment = require("../../Environment")

local STAGE: string = "tests/Fixtures/Npcs/Stage.luau"
local CASTS: string = "tests/Fixtures/Step/Collision.luau"
local GEOMETRY: string = "tests/Fixtures/Step/Geometry.luau"
local STEP: number = 1 -- Seconds the stand-in clock moves on at each read
local ROOMY: number = 1e6 -- A budget no walk of two NPCs spends on the stand-in clock
local SPENT: number = 0 -- One spent at the first read, so every NPC not forced waits
local SPACING: number = 20 -- Studs between the two NPCs along Z
local POST_SIZE: vector = vector.create(1, 8, 1) -- Narrower than the hull and taller, so only the exact check finds it
local SETTLED: number = 11 -- The tick after which the still NPC has a first part moved into it
local OFF_TENTH: number = 20 -- The tenth tick that frees it with no budget
local CROSSED: number = 30 -- The last tick with no budget, itself a tenth
local ROOMY_TENTH: number = 40 -- The tenth tick that frees it from the second part, a roomy budget set
local WAITED_TENTH: number = 50 -- A tenth tick every NPC waits on under a spent budget, which is then cleared
local CLEARED_TENTH: number = 60 -- The tenth tick that frees it from the third part

-- Casts over the fixture's parts with one post standing at a spot
local function posted(Casts: any, Geometry: any, at: vector): any
	local parts: { any } = table.clone(Geometry.parts)
	table.insert(parts, {
		name = "Post",
		center = vector.create(at.x, Geometry.floor + POST_SIZE.y / 2, at.z),
		size = POST_SIZE,
		tilt = 0,
	})

	return Casts(parts)
end

--[[
    Steps the ticks from first to last, every NPC stepping on each, and
    gives why the still one left where it stood on any but freedOn, or
    stayed there on freedOn, or nil; with no freedOn it never moves
--]]

local function through(stage: any, npcs: { any }, still: any, first: number, last: number, freedOn: number?): string?
	local spot: vector = still:getState().position

	for tick: number = first, last do
		stage.Npcs.step(tick)

		for _, npc: any in npcs do
			if npc:getState().tick ~= tick then
				return `The NPC in slot {npc.slot} last stepped on tick {npc:getState().tick}, not {tick}`
			end
		end

		local moved: boolean = still:getState().position ~= spot
		if moved ~= (tick == freedOn) then
			return `The still NPC moved {moved} on tick {tick}, where the part frees it on tick {freedOn}`
		elseif moved then
			spot = still:getState().position
		end
	end

	return nil
end

return function (): (boolean, string | nil)
	local stage: any = Environment.load(STAGE)
	local Casts: any = Environment.load(CASTS)
	local Geometry: any = Environment.load(GEOMETRY)
	local clock: any = stage.clock(STEP)
	stage.start(clock.read)

	local still: any = stage.Npcs.create(vector.create(-20, stage.resting, -SPACING / 2), 0)
	local other: any = stage.Npcs.create(vector.create(-20, stage.resting, SPACING / 2), 0)
	local npcs: { any } = { still, other }

	-- Its first step rounds its feet onto the quantum, and from then on it stands still
	stage.Npcs.step(1)

	local failure: string? = through(stage, npcs, still, 2, SETTLED, nil)
	if failure then
		return false, `Settling: {failure}`
	end

	stage.world.collision = posted(Casts, Geometry, still:getState().position)
	failure = through(stage, npcs, still, SETTLED + 1, CROSSED, OFF_TENTH)
	if failure then
		return false, `With no budget: {failure}`
	elseif clock.reads ~= 0 then
		return false, `The ticks with no budget read the clock {clock.reads} times, not 0`
	elseif stage.Npcs.waited() ~= 0 then
		return false, `The ticks with no budget counted {stage.Npcs.waited()} waits, not 0`
	end

	-- A check owed from the ticks with no budget would free it on the first budgeted step
	stage.world.collision = posted(Casts, Geometry, still:getState().position)
	stage.Npcs.setBudget(ROOMY)
	failure = through(stage, npcs, still, CROSSED + 1, ROOMY_TENTH, ROOMY_TENTH)
	if failure then
		return false, `With a roomy budget: {failure}`
	end

	failure = through(stage, npcs, still, ROOMY_TENTH + 1, WAITED_TENTH - 1, nil)
	if failure then
		return false, `Before the spent budget: {failure}`
	end

	-- Both wait on a tenth tick, so both owe the check, and the budget is cleared before either steps
	stage.world.collision = posted(Casts, Geometry, still:getState().position)
	stage.Npcs.setBudget(SPENT)
	stage.Npcs.step(WAITED_TENTH)
	for _, npc: any in npcs do
		if npc:getState().tick == WAITED_TENTH then
			return false, `The NPC in slot {npc.slot} stepped on tick {WAITED_TENTH} under a spent budget`
		end
	end

	stage.Npcs.setBudget(nil)
	failure = through(stage, npcs, still, WAITED_TENTH + 1, WAITED_TENTH + 1, nil)
	if failure then
		return false, `With the budget cleared: {failure}`
	end

	-- Their forced steps under a budget set again run no check the cleared one left owed
	stage.Npcs.setBudget(ROOMY)
	failure = through(stage, npcs, still, WAITED_TENTH + 2, CLEARED_TENTH, CLEARED_TENTH)
	if failure then
		return false, `With a budget set again: {failure}`
	end

	local report: any = stage.reports[1]
	if report then
		return false, `The stage reported {report.kind} {report.measurement}, where every NPC was freed`
	end

	return true, nil
end
