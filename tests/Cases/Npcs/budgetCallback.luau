--[[
    A budgeted walk goes over the NPCs as they stood when it began: one a
    landing callback destroys later in the walk takes no turn, step or wait,
    and one it makes takes its first turn on the next tick, as any other
--]]

--!strict
local Environment = require("../../Environment")

local STAGE: string = "tests/Fixtures/Npcs/Stage.luau"
local STEP: number = 1 -- Seconds the stand-in clock moves on at each read
local BUDGET: number = 0 -- Spent at the first read, so the NPCs wait together and step together, tick about
local DROP: number = 10 -- Studs above the floor the faller starts
local TICK_LIMIT: number = 80 -- Ticks enough for that fall to land stepping every other tick, at 40 steps
local FALLER_Z: number = -20
local VICTIM_Z: number = -5 -- The NPC the landing destroys, in the slot after the faller's
local OTHER_Z: number = 5
local NEW_Z: number = 15 -- Where the landing makes an NPC

-- The live NPCs' slots in the order Npcs.each visits them, as one line
local function visited(stage: any): string
	local slots: { string } = {}
	stage.Npcs.each(function (npc: any)
		table.insert(slots, `{npc.slot}`)
	end)

	return table.concat(slots, " ")
end

return function (): (boolean, string | nil)
	local stage: any = Environment.load(STAGE)
	stage.start(stage.clock(STEP).read)

	local faller: any = stage.Npcs.create(vector.create(-20, stage.geometry.floor + DROP, FALLER_Z), 0)
	local victim: any = stage.Npcs.create(vector.create(-20, stage.resting, VICTIM_Z), 0)
	local other: any = stage.Npcs.create(vector.create(-20, stage.resting, OTHER_Z), 0)
	stage.Npcs.setBudget(BUDGET)

	local tick: number = 0
	local landedOn: number? = nil
	local made: any = nil
	stage.landed = function (npc: any, _: number)
		if npc == faller and landedOn == nil then
			landedOn = tick
			victim:destroy()
			made = stage.Npcs.create(vector.create(-20, stage.resting, NEW_Z), 0)
		end
	end

	-- The faller waits on the odd ticks and steps on the even ones, so it lands on an even tick, stepping forced
	local before: number = 0
	while landedOn == nil and tick < TICK_LIMIT do
		before = stage.Npcs.waited()
		tick += 1
		stage.Npcs.step(tick)
	end

	if landedOn == nil then
		return false, `The faller had not landed after {tick} ticks`
	elseif tick % 2 ~= 0 then
		return false, `The faller landed on tick {tick}, an odd one, where it waits`
	end

	-- That tick: the destroyed NPC, after the faller in the walk, took no turn, and the new one took none either
	if victim:getState().tick == tick then
		return false, `The NPC the landing destroyed still stepped on tick {tick}`
	elseif other:getState().tick ~= tick or faller:getState().tick ~= tick then
		return false, `The NPCs left did not step forced on tick {tick}`
	elseif made:getState().tick == tick then
		return false, `The NPC the landing made stepped on tick {tick}, the tick it was made`
	elseif stage.Npcs.waited() ~= before then
		return false, `The landing's tick counted {stage.Npcs.waited() - before} waits, not none`
	elseif visited(stage) ~= `{faller.slot} {other.slot} {made.slot}` then
		return false, `After the landing the NPCs are {visited(stage)}, not the faller, the other and the new one`
	end

	-- The next tick the new NPC takes its first turn, not forced, and waits with the others; the tick after, all step
	local left: { any } = { faller, other, made }
	before = stage.Npcs.waited()
	tick += 1
	stage.Npcs.step(tick)

	for _, npc: any in left do
		if npc:getState().tick == tick then
			return false, `The NPC in slot {npc.slot} stepped on tick {tick} under the spent budget`
		end
	end

	if stage.Npcs.waited() ~= before + #left then
		return false, `The tick after the landing counted {stage.Npcs.waited() - before} waits, not {#left}`
	end

	tick += 1
	stage.Npcs.step(tick)

	for _, npc: any in left do
		if npc:getState().tick ~= tick then
			return false, `The NPC in slot {npc.slot} did not step forced on tick {tick}`
		end
	end

	return true, nil
end
