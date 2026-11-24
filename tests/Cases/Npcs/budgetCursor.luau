--[[
    A budgeted walk starts at the first NPC whose slot is the cursor's or
    above: past a destroyed NPC's slot, at a new NPC that reuses it, which
    no wait of the old one forces, and round to the first past the last
--]]

--!strict
local Environment = require("../../Environment")

local STAGE: string = "tests/Fixtures/Npcs/Stage.luau"
local CONSTANTS: string = "src/Constants.luau"
local STEP: number = 1 -- Seconds the stand-in clock moves on at each read
local ONE: number = 1.5 -- Spent at a walk's third read, so one NPC not forced steps a tick
local THREE: number = 3.5 -- Spent at a walk's fifth read, so three do
local COUNT: number = 4
local WIDER: number = 5 -- NPCs for the walk that goes round past the last slot
local SPACING: number = 10 -- Studs between the NPCs along Z
local NEW_Z: number = -20 -- Where the NPC that reuses a slot is made, clear of the others

-- A stage on the stand-in clock with count NPCs along Z in slots 0 on, centered on the floor
local function staged(count: number): (any, { any })
	local stage: any = Environment.load(STAGE)
	stage.start(stage.clock(STEP).read)

	local npcs: { any } = {}
	for index: number = 1, count do
		local z: number = (index - (count + 1) / 2) * SPACING
		table.insert(npcs, stage.Npcs.create(vector.create(-20, stage.resting, z), 0))
	end

	return stage, npcs
end

-- Why the slots of the NPCs that did not step on each tick in turn are not the ones expected, or nil
local function expect(stage: any, npcs: { any }, first: number, expected: { string }, label: string): string?
	for offset: number, wanted: string in expected do
		local tick: number = first + offset - 1
		stage.Npcs.step(tick)

		local slots: { number } = {}
		for _, npc: any in npcs do
			if npc:getState().tick ~= tick then
				table.insert(slots, npc.slot)
			end
		end

		table.sort(slots)

		local waited: string = table.concat(slots, " ")
		if waited ~= wanted then
			return `{label}: on tick {tick} the NPCs in slots "{waited}" waited, not "{wanted}"`
		end
	end

	return nil
end

return function (): (boolean, string | nil)
	-- The NPC in slot 1 is the first to wait, so the cursor is 1, and it is destroyed: the walk starts at slot 2
	local stage: any, npcs: { any } = staged(COUNT)
	stage.Npcs.setBudget(ONE)

	local failure: string? = expect(stage, npcs, 1, { "1 2 3" }, "Four NPCs")
	if failure then
		return false, failure
	end

	npcs[2]:destroy()
	table.remove(npcs, 2)

	failure = expect(stage, npcs, 2, { "", "0 3", "", "0 2" }, "With the cursor's NPC destroyed")
	if failure then
		return false, failure
	end

	-- The same start, then a new NPC takes slot 1 once every never-used slot is taken: the walk starts at it, and
	-- the wait of the NPC destroyed there does not force it
	stage, npcs = staged(COUNT)
	stage.Npcs.setBudget(ONE)
	failure = expect(stage, npcs, 1, { "1 2 3" }, "Four NPCs")
	if failure then
		return false, failure
	end

	local destroyed: any = npcs[2]
	destroyed:destroy()

	-- Every slot past the NPCs made
	for _ = #npcs, Environment.load(CONSTANTS).SLOTS - 1 do
		stage.Slots.take("Body")
	end

	local reused: any = stage.Npcs.create(vector.create(-20, stage.resting, NEW_Z), 0)
	if reused.slot ~= destroyed.slot then
		return false, `The new NPC took slot {reused.slot}, not the destroyed one's slot {destroyed.slot}`
	end

	npcs[2] = reused

	failure = expect(stage, npcs, 2, { "0" }, "With the cursor's slot reused")
	if failure then
		return false, failure
	end

	-- The cursor lands on slot 3, and slots 3 and 4 are destroyed: the walk goes round to slot 0
	stage, npcs = staged(WIDER)
	stage.Npcs.setBudget(THREE)
	failure = expect(stage, npcs, 1, { "3 4" }, "Five NPCs")
	if failure then
		return false, failure
	end

	local cursor: number = 3 -- The first slot that waited, where the next walk starts
	for index: number = #npcs, 1, -1 do
		if npcs[index].slot >= cursor then
			table.remove(npcs, index):destroy()
		end
	end

	stage.Npcs.setBudget(ONE)

	failure = expect(stage, npcs, 2, { "1 2" }, "With the cursor past the last slot")
	if failure then
		return false, failure
	end

	return true, nil
end
