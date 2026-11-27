--[[
    With no budget the walk reads no clock and steps every awake NPC every
    tick as a stage with no clock does, a budget set then cleared is off
    again, and a budget or clock Npcs cannot run on is refused
--]]

--!strict
local Environment = require("../../Environment")

local STAGE: string = "tests/Fixtures/Npcs/Stage.luau"
local STEP: number = 1 -- Seconds the stand-in clock moves on at each read
local BUDGET: number = 2.5 -- A budget set, then cleared before the first tick
local COUNT: number = 3 -- NPCs walking on each stage
local SPACING: number = 10 -- Studs between them along Z
local TICKS: number = 12
local BUDGET_REFUSAL: string = "Npcs.setBudget takes nil or a finite number of seconds of 0 or more"

type Refusal = {
	label: string,
	call: () -> (),
	refusal: string,
}

-- Why a call that should refuse ran, or failed with another message, or nil
local function refuses(refusal: Refusal): string?
	local ran: boolean, message: any = pcall(refusal.call)
	if ran then
		return `{refusal.label} was taken`
	elseif not string.find(`{message}`, refusal.refusal, 1, true) then
		return `{refusal.label} was refused with something other than "{refusal.refusal}": {message}`
	end

	return nil
end

-- The NPCs of one stage, made and commanded to walk ahead the same way on every stage
local function walkers(stage: any): { any }
	local order: any = stage.order()
	order.forward = 1

	local npcs: { any } = {}
	for index: number = 1, COUNT do
		local npc: any = stage.Npcs.create(vector.create(-20, stage.resting, (index - 1) * SPACING), 0)
		npc:command(order)
		table.insert(npcs, npc)
	end

	return npcs
end

return function (): (boolean, string | nil)
	local timed: any = Environment.load(STAGE)
	local plain: any = Environment.load(STAGE)
	local clock: any = timed.clock(STEP)
	local Npcs: any = timed.Npcs

	local early: string? = refuses({
		label = "a start with a clock that is no function",
		call = function ()
			Npcs.start(timed.world, function () end, "os.clock")
		end,
		refusal = "Npcs.start takes the clock as a function giving seconds",
	})
	if early then
		return false, early
	end

	timed.start(clock.read)
	plain.start()

	if Npcs.budget() ~= nil then
		return false, `A new stage's budget was {Npcs.budget()}, not off`
	end

	local budgets: { Refusal } = {
		{
			label = "a negative budget",
			call = function ()
				Npcs.setBudget(-STEP)
			end,
			refusal = BUDGET_REFUSAL,
		},
		{
			label = "a budget that is not a number",
			call = function ()
				Npcs.setBudget(0 / 0)
			end,
			refusal = BUDGET_REFUSAL,
		},
		{
			label = "an infinite budget",
			call = function ()
				Npcs.setBudget(math.huge)
			end,
			refusal = BUDGET_REFUSAL,
		},
		{
			label = "a budget given as a string",
			call = function ()
				Npcs.setBudget(`{BUDGET}`)
			end,
			refusal = BUDGET_REFUSAL,
		},
	}

	for _, refusal: Refusal in budgets do
		local failure: string? = refuses(refusal)
		if failure then
			return false, failure
		elseif Npcs.budget() ~= nil then
			return false, `{refusal.label} turned the cap on at {Npcs.budget()}`
		end
	end

	Npcs.setBudget(BUDGET)
	if Npcs.budget() ~= BUDGET then
		return false, `A budget of {BUDGET} s read back as {Npcs.budget()}`
	end

	Npcs.setBudget(nil)
	if Npcs.budget() ~= nil then
		return false, `A budget cleared with nil read back as {Npcs.budget()}`
	end

	local timedNpcs: { any } = walkers(timed)
	local plainNpcs: { any } = walkers(plain)

	for tick: number = 1, TICKS do
		timed.Npcs.step(tick)
		plain.Npcs.step(tick)

		for index: number = 1, COUNT do
			local state: any = timedNpcs[index]:getState()
			local control: any = plainNpcs[index]:getState()

			if state.tick ~= tick then
				return false, `NPC {index} with the cap off last stepped on tick {state.tick}, not {tick}`
			elseif state.position ~= control.position or state.velocity ~= control.velocity then
				return false,
					`NPC {index} with the cap off stood at {state.position} on tick {tick}, not {control.position}`
			end
		end
	end

	if clock.reads ~= 0 then
		return false, `The walk with the cap off read the clock {clock.reads} times, not 0`
	elseif Npcs.waited() ~= 0 then
		return false, `The walk with the cap off counted {Npcs.waited()} waits, not 0`
	end

	return true, nil
end
