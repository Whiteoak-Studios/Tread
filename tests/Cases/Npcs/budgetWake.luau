--[[
    An NPC that waited, then slept through a tick, keeps its wait: woken,
    its first turn back steps forced whatever the time, though it did not
    wait the tick before, and the turn after is an ordinary one
--]]

--!strict
local Environment = require("../../Environment")

local STAGE: string = "tests/Fixtures/Npcs/Stage.luau"
local STEP: number = 1 -- Seconds the stand-in clock moves on at each read
local BUDGET: number = 0 -- Spent at the first read, so every NPC not forced waits
local SPACING: number = 10 -- Studs between the NPCs along Z

type Turn = "steps" | "waits" | "sleeps"
type Tally = { waits: number }

-- Steps one tick and gives why an NPC's turn on it was not the one given, or nil, adding each wait to the tally
local function run(stage: any, npcs: { any }, tick: number, turns: { Turn }, label: string, tally: Tally): string?
	stage.Npcs.step(tick)

	for index: number, npc: any in npcs do
		local turn: Turn = turns[index]
		local stepped: boolean = npc:getState().tick == tick
		if stepped ~= (turn == "steps") then
			return `{label}: the NPC in slot {npc.slot} stepped {stepped} on tick {tick}, where it {turn}`
		elseif turn == "waits" then
			tally.waits += 1
		end
	end

	return nil
end

return function (): (boolean, string | nil)
	local stage: any = Environment.load(STAGE)
	stage.start(stage.clock(STEP).read)

	-- The reader is first in the walk, so the budget is spent before the sleeper's turn
	local reader: any = stage.Npcs.create(vector.create(-20, stage.resting, -SPACING / 2), 0)
	local sleeper: any = stage.Npcs.create(vector.create(-20, stage.resting, SPACING / 2), 0)
	local npcs: { any } = { reader, sleeper }
	local tally: Tally = { waits = 0 }
	stage.Npcs.setBudget(BUDGET)

	local failure: string? = run(stage, npcs, 1, { "waits", "waits" }, "Both waiting", tally)
	if failure then
		return false, failure
	end

	sleeper:setAwake(false)
	failure = run(stage, npcs, 2, { "steps", "sleeps" }, "The sleeper asleep", tally)
	if failure then
		return false, failure
	end

	-- The reader waits as the budget is spent, and the woken sleeper still steps after it
	sleeper:setAwake(true)
	failure = run(stage, npcs, 3, { "waits", "steps" }, "The sleeper's first tick back", tally)
	if failure then
		return false, failure
	end

	failure = run(stage, npcs, 4, { "steps", "waits" }, "The tick after", tally)
	if failure then
		return false, failure
	elseif stage.Npcs.waited() ~= tally.waits then
		return false, `Npcs.waited gave {stage.Npcs.waited()}, not the {tally.waits} waits seen`
	end

	return true, nil
end
