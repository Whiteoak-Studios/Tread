--[[
    A lever whose getter throws never leaves a flip partway: it is not set,
    not in the states and named among the refusals, and a lever line that
    throws in a header still has the levers put back before the run fails
--]]

--!strict
local Step = require("../../Fixtures/DevStep/Step")

local READ: string = "a stand-in read" -- What a throwing getter throws

-- A live lever of a session that keeps each state it is set to, from the one given, logging each set
local function kept(name: string, session: number, state: boolean, sets: { string }): any
	local on: boolean = state

	return {
		name = name,
		session = session,
		live = true,
		get = function (): boolean
			return on
		end,
		set = function (value: boolean)
			on = value
			table.insert(sets, `{name} {value}`)
		end,
	}
end

-- A live lever of a session whose getter always throws, logging any set it is given
local function unreadable(name: string, session: number, sets: { string }): any
	return {
		name = name,
		session = session,
		live = true,
		get = function (): boolean
			error(READ, 0)
		end,
		set = function (value: boolean)
			table.insert(sets, `{name} {value}`)
		end,
	}
end

-- Each state a flip found, by name, in name order
local function foundOf(states: { [string]: boolean }): string
	local found: { string } = {}
	for name: string, state: boolean in states do
		table.insert(found, `{name} {state}`)
	end

	table.sort(found)

	return table.concat(found, ",")
end

-- Each half drives, the after half showing verdict memory, so only a throw can fail the run
local function answer(_: string, half: string?): (boolean, string, { [string]: number }?)
	local remembered: number = 0
	if half == "after" then
		remembered = 1
	end

	return true, "drove and cleaned up", { skipped = 1, antiEspKept = remembered }
end

-- Makes the boot lever changes' getter throw whenever the predicate holds, as a lever line read mid-flip would
local function throwWhen(mounted: Step.Mounted, predicate: () -> boolean)
	for _, lever: any in mounted.Levers.list do
		if lever.name == "changes" then
			lever.get = function (): boolean
				if predicate() then
					error(READ, 0)
				end

				return true
			end
		end
	end
end

return function (): (boolean, string | nil)
	-- 1) A flip over a lever whose getter throws sets the others, off in the list's reverse order, leaves it unset and
	-- out of the states, and names it, by session and by its own name, never as a name no lever has
	local mounted: Step.Mounted = Step.load(answer)
	local Levers: any = mounted.Levers
	local sets: { string } = {}
	Levers.list = { kept("first", 3, true, sets), unreadable("second", 3, sets), kept("third", 3, true, sets) }

	local flipped: boolean, states: any, refused: any = pcall(Levers.flip, 3, false)
	if not flipped then
		return false, `A flip over a lever whose getter throws threw: {states}`
	elseif foundOf(states) ~= "first true,third true" or table.concat(sets, ",") ~= "third false,first false" then
		return false, `The flip found {foundOf(states)} and set {table.concat(sets, ",")}`
	elseif table.concat(refused, ",") ~= `second refused a read: {READ}` then
		return false, `The flip refused {table.concat(refused, ",")}`
	end

	-- Restore puts the on states back in the list's order
	Levers.restore(states)
	if table.concat(sets, ",") ~= "third false,first false,first true,third true" then
		return false, `After restore the sets were {table.concat(sets, ",")}`
	end

	local byName: { [string]: boolean }, nameRefused: { string } = Levers.flip(3, true, "second")
	if next(byName) ~= nil or table.concat(nameRefused, ",") ~= `second refused a read: {READ}` then
		return false, `A flip of second by name found {foundOf(byName)} and refused {table.concat(nameRefused, ",")}`
	end

	-- 2) The noise run's first flip meets that getter: it still sets the rest, the run fails naming the throw, and the
	-- lever it set is put back
	local noise: Step.Mounted = Step.load(answer)
	local noiseSets: { string } = {}
	local first: any = kept("first", 3, false, noiseSets)
	noise.Levers.list = { first, unreadable("second", 3, noiseSets) }

	local ran: boolean, passed: any, reason: any = pcall(noise.BenchStepNoise)
	local text: string = tostring(reason)
	if not ran then
		return false, `A noise run whose first flip met a throwing getter threw: {passed}`
	elseif passed then
		return false, "A noise run whose lever line threw passed"
	elseif not string.find(text, "Step benchmark noise run threw: ", 1, true) then
		return false, `A noise run whose lever line threw gave:\n{text}`
	elseif not string.find(text, `second refused a read: {READ}`, 1, true) then
		return false, `A noise run whose getter threw named no refusal:\n{text}`
	elseif first.get() ~= false or table.concat(noiseSets, ",") ~= "first true,first false" then
		return false, `The noise run left first {first.get()} after setting {table.concat(noiseSets, ",")}`
	end

	-- 3) The step benchmark's header line throws with its before half's levers set: they are put back, and the run
	-- fails naming the throw
	local step: Step.Mounted = Step.load(answer)
	throwWhen(step, function (): boolean
		return step.Relay.budget() == nil
	end)

	passed, reason = step.BenchStep()
	text = tostring(reason)
	local capped: boolean = step.AntiEsp.wholeOn()
		and step.Npcs.budget() ~= nil
		and step.Relay.budget() ~= nil
		and step.Relay.underLoad() ~= nil

	if passed or not string.find(text, `Step benchmark threw: {READ}`, 1, true) then
		return false, `A step benchmark whose header line threw gave {passed}:\n{text}`
	elseif not capped then
		return false, "A step benchmark whose header line threw left the session's levers as its before half sets them"
	end

	-- 4) The memory run's header line throws with verdict memory set on for its after half: it is put back off
	local memory: Step.Mounted = Step.load(answer)
	throwWhen(memory, function (): boolean
		return memory.AntiEsp.memoryOn()
	end)

	passed, reason = memory.BenchStep("memory")
	text = tostring(reason)
	if passed or not string.find(text, `Step benchmark verdict memory run threw: {READ}`, 1, true) then
		return false, `A memory run whose header line threw gave {passed}:\n{text}`
	elseif memory.AntiEsp.memoryOn() then
		return false, "A memory run whose header line threw left verdict memory on"
	elseif #memory.asked > 0 then
		return false, "A memory run whose header threw still ran a half"
	end

	return true, nil
end
