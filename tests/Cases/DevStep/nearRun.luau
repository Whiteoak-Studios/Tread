--[[
    The near rate run takes S3 alone, before then after, with anti-ESP's
    workers flipped alone through their lever and every other lever as the
    server has it, its table titled by that lever, and the workers put back
--]]

--!strict
local Step = require("../../Fixtures/DevStep/Step")

local LOAD: string = "S3"
local NAME: string = "antiEspWorkers"
local GONE: string = "nearRate60" -- No lever, line or table names it
local TITLE: string = "Step benchmark near rate run session 3, "
local CAPS: string = "true 0.001 0.005 20/0.5" -- The frame caps as the stand-in server starts them
local NOTE: string =
	"; anti-ESP retests each near hidden pair once a server tick, at the first slice after the bodies step; before: "
local CLOSING: string = `{LOAD} {NAME} table, figure: before after change percent\n`

-- Each half's mark in the figures it gives, so the table's columns show whose they hold
local MARKS: { [string]: number } = { before = 100, after = 200 }
local MARKED: string = "\ncommands lazy decode skipped: 100 200 +100 +100.0%"

-- Each half drives and gives its mark, but the call numbered throwing throws
local function answers(throwing: number?): Step.Answer
	local calls: number = 0

	return function (_: string, half: string?): (boolean, string, { [string]: number }?)
		calls += 1
		if calls == throwing then
			error("a stand-in throw", 0)
		end

		return true, "drove and cleaned up", { skipped = MARKS[half :: string] }
	end
end

-- Each half's anti-ESP workers, in the order the halves ran
local function workersOf(asked: { Step.Asked }): string
	local found: { string } = {}
	for _, half: Step.Asked in asked do
		table.insert(found, `{half.half} {half.antiEsp}`)
	end

	return table.concat(found, ",")
end

return function (): (boolean, string | nil)
	-- 1) Through its scenario: S3 before then after on the relay's workers, anti-ESP's workers alone off then on,
	-- every other lever as the server started them, then its table, and the workers put back
	local mounted: Step.Mounted = Step.load(answers(nil))
	local passed: boolean, reason: string? = mounted.BenchStepNear()
	local order: string = table.concat(mounted.events, "\n", 2, 3)
	local closing: string? = mounted.events[4]
	if not passed then
		return false, `A near rate run whose halves drove failed: {reason}`
	elseif order ~= `half {LOAD}/before\nhalf {LOAD}/after` or #mounted.events ~= 4 then
		return false, `The near rate run went:\n{table.concat(mounted.events, "\n")}`
	elseif not closing or string.find(closing, CLOSING, 1, true) ~= 1 then
		return false, `The near rate run closed on:\n{closing}`
	elseif not string.find(closing, MARKED, 1, true) then
		return false, `The near rate run's table read otherwise than before then after:\n{closing}`
	elseif workersOf(mounted.asked) ~= "before false,after true" then
		return false, `The near rate run's halves ran with anti-ESP's workers {workersOf(mounted.asked)}`
	end

	for _, asked: Step.Asked in mounted.asked do
		local name: string = `{asked.scenario}/{asked.half}`
		if asked.scenario ~= LOAD or asked.workers ~= true or asked.timing ~= mounted.Config.step.timing then
			return false, `{name} was asked for with workers {asked.workers} and its own timing`
		elseif Step.asked(asked) ~= CAPS or asked.split or asked.memory then
			return false, `{name} ran with the caps {Step.asked(asked)}, the split or verdict memory otherwise`
		elseif asked.bands ~= 3 or not asked.crowd or not asked.lazy or not asked.checks then
			return false, `{name} ran with a lever of session 1 or 2 otherwise than the server has it`
		end
	end

	if mounted.AntiEsp.workersOn() then
		return false, "The near rate run left anti-ESP's workers on"
	elseif Step.caps(mounted) ~= CAPS then
		return false, `The near rate run left the caps {Step.caps(mounted)}`
	end

	-- 2) The header: its title, the near rechecks' note, and the workers named off before and on after, with no lever
	-- as the run found it and none of a near rate
	local header: string = mounted.events[1]
	local at: number? = string.find(header, "; after: ", 1, true)
	local before: string = string.sub(header, 1, at or 0)
	local after: string = string.sub(header, at or #header + 1)
	if string.sub(header, 1, #TITLE) ~= TITLE or not string.find(header, NOTE, 1, true) then
		return false, `The near rate run's header read:\n{header}`
	elseif not string.find(before, `{NAME} (session 2, live) off, `, 1, true) then
		return false, `The near rate run's header named no before half with the workers off:\n{header}`
	elseif not string.find(after, `{NAME} (session 2, live) on, `, 1, true) then
		return false, `The near rate run's header named no after half with the workers on:\n{header}`
	elseif string.find(header, "as the run found them", 1, true) then
		return false, `The near rate run's header named the levers as it found them:\n{header}`
	end

	-- 3) No lever, line or table of any run names a near rate
	for _, lever: any in mounted.Levers.list do
		if lever.name == GONE then
			return false, `{GONE} is listed as a lever`
		end
	end

	for _, event: string in mounted.events do
		if string.find(event, GONE, 1, true) then
			return false, `A line of the near rate run named {GONE}:\n{event}`
		end
	end

	local other: Step.Mounted = Step.load(answers(nil))
	other.BenchStep()
	other.BenchStepNoise()
	other.BenchStepLevers()
	for _, event: string in other.events do
		if string.find(event, GONE, 1, true) then
			return false, `A line of another step run named {GONE}:\n{event}`
		end
	end

	-- 4) Started with the workers on, the halves still run off then on, and the workers are put back on
	local opposite: Step.Mounted = Step.load(answers(nil))
	opposite.AntiEsp.useWorkers(true)
	opposite.BenchStepNear()
	if workersOf(opposite.asked) ~= "before false,after true" then
		return false, `Started with the workers on, the halves ran with them {workersOf(opposite.asked)}`
	elseif not opposite.AntiEsp.workersOn() then
		return false, "Started with the workers on, the near rate run left them off"
	end

	-- 5) The after half throws: the run fails naming it, and the workers are put back off
	local thrown: Step.Mounted = Step.load(answers(2))
	local threw: boolean, why: string? = thrown.BenchStepNear()
	if threw then
		return false, "A near rate run whose after half threw passed"
	elseif not string.find(why or "", `Bots {LOAD}/after: it threw: a stand-in throw`, 1, true) then
		return false, `A near rate run whose after half threw gave:\n{why}`
	elseif #thrown.asked ~= 2 or thrown.AntiEsp.workersOn() then
		return false,
			`After a thrown half, {#thrown.asked} halves ran and the workers stood {thrown.AntiEsp.workersOn()}`
	end

	return true, nil
end
