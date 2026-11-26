--[[
    The near-rate run takes S3 twice, the raised near rate off then on with
    anti-ESP's workers held off and on then off with them held on, titles
    each table by its hold, and puts the rate and the workers back
--]]

--!strict
local Step = require("../../Fixtures/DevStep/Step")

local NAME: string = "nearRate60"
local WORKERS: string = "antiEspWorkers"
local TITLE: string = "Step benchmark near rate run session 3, "
local DATE: string = "^(%d%d%d%d%-%d%d%-%d%d) UTC, " -- The header's UTC date, after its title and session
local SERVER_RATE: number = 30 -- Hz, the stand-in server's antiEsp.nearRate, which anti-ESP starts on
local RAISED: number = 60 -- Hz, the bench's raised near rate
local OTHER_RATE: number = 20 -- Hz, a server rate the stand-in's settings are changed to, unlike the one it started on
local CAPS: string = "true 0.001 0.005 20/0.5" -- The frame caps as the stand-in server starts them
local REFUSAL: string = "a stand-in refusal"

-- What the run printed and asked for, in order: each load's two halves, then its table titled by its lever and hold
local ORDER: { string } = {
	"header",
	"half S3/before",
	"half S3/after",
	"S3 nearRate60, antiEspWorkers off table",
	"half S3/after",
	"half S3/before",
	"S3 nearRate60, antiEspWorkers on table",
}

-- Each half's near rate in Hz and whether anti-ESP's workers were on, in the order the halves ran
local HALVES: string = "30 false,60 false,60 true,30 true"
local OTHER_HALVES: string = "20 false,60 false,60 true,20 true" -- With the server's rate changed to OTHER_RATE

-- The header after its date: the server, the build's notes with the near rates, and every lever as the run found it
local SERVER: string = "place version 412, job job-1, 0 real players in, 4 relay workers started, "
	.. "2 anti-ESP workers made"
local NOTES: string = table.concat({
	"the worker clock's unpack section holds each worker's read of its own hand-in",
	"with relayBudget on, a viewer's turn after a run that left it can carry that run's footsteps, which raises the "
		.. "bytes rows and leaves the records rows alone",
	"with nearRate60 on, anti-ESP retests a near hidden pair at 60 Hz, and off at the server's antiEsp.nearRate of "
		.. "30 Hz",
}, "; ")
local FOUND: string = "as the run found them, before each load holds the levers its table names: "
local LEVERS: string = table.concat({
	"lazyDecode (session 1, live) on",
	"ownerChecks (session 1, live) on",
	"relayWorkers (session 0, boot) on",
	"relayClocks (session 1, boot) on",
	"outOfView (session 0, boot) on",
	"changes (session 0, boot) on",
	"bands (session 2, live) on",
	"crowdCap (session 2, live) on",
	"antiEspWorkers (session 2, live) off",
	"verdictMemory (session 2, live) off",
	"stageSplit (session 3, live) off",
	"antiEspWhole (session 3, live) on",
	"npcBudget (session 3, live) on",
	"relayBudget (session 3, live) on",
	"farUnderLoad (session 3, live) on",
	"nearRate60 (session 3, live) off",
}, ", ")

-- Each half's mark in the figures it gives, so a table's columns show whose they hold
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

-- Each event as the order names it: a half as asked, a table by its title, and the first line as the header
local function eventsOf(events: { string }): string
	local named: { string } = {}
	for index: number, event: string in events do
		local title: string? = string.match(event, "^(.-) table, figure: ")
		if index == 1 then
			table.insert(named, "header")
		elseif title then
			table.insert(named, `{title} table`)
		else
			table.insert(named, event)
		end
	end

	return table.concat(named, ",")
end

-- Each half's near rate and anti-ESP's workers, as HALVES gives them
local function halvesOf(asked: { Step.Asked }): string
	local found: { string } = {}
	for _, half: Step.Asked in asked do
		table.insert(found, `{half.nearRate} {half.antiEsp}`)
	end

	return table.concat(found, ",")
end

-- The lever of that name
local function leverOf(Levers: any, name: string): any
	for _, lever: any in Levers.list do
		if lever.name == name then
			return lever
		end
	end

	return nil
end

return function (): (boolean, string | nil)
	-- 1) The lever: session 3's, live, alone and last, on only at the raised rate exactly, which a flip by name sets,
	-- its restore puts back to the server's, and a session's flip leaves alone
	local mounted: Step.Mounted = Step.load(answers(nil))
	local Levers: any = mounted.Levers
	local AntiEsp: any = mounted.AntiEsp
	local lever: any = leverOf(Levers, NAME)

	if lever == nil or Levers.list[#Levers.list] ~= lever then
		return false, `{NAME} is not the list's last lever`
	elseif lever.session ~= 3 or lever.live ~= true or lever.alone ~= true then
		return false, `{NAME} is session {lever.session}, live {lever.live} and alone {lever.alone}`
	elseif AntiEsp.nearRate() ~= SERVER_RATE or lever.get() then
		return false, `Anti-ESP started at {AntiEsp.nearRate()} Hz with {NAME} reading {lever.get()}`
	end

	for _, on: boolean in { false, true } do
		local found: { [string]: boolean } = Levers.flip(3, on)
		if AntiEsp.nearRate() ~= SERVER_RATE or found[NAME] ~= nil then
			return false, `Session 3's flip {on} set the near rate to {AntiEsp.nearRate()} Hz`
		end

		Levers.restore(found)
	end

	local states: { [string]: boolean }, refused: { string } = Levers.flip(3, true, NAME)
	if AntiEsp.nearRate() ~= RAISED or not lever.get() or states[NAME] ~= false or #refused > 0 then
		return false, `The flip by name set {AntiEsp.nearRate()} Hz, refusing {table.concat(refused, ", ")}`
	end

	Levers.restore(states)
	if AntiEsp.nearRate() ~= SERVER_RATE or lever.get() then
		return false, `The flip by name's restore left the near rate at {AntiEsp.nearRate()} Hz`
	end

	-- 2) Through its scenario: S3's four halves in order on the relay's workers with the step's timing, 30 then 60 with
	-- the workers held off and 60 then 30 with them held on, every other lever as the server has them, each table
	-- titled by its hold with the before half in its before column, and the rate and the workers put back
	local passed: boolean, reason: string? = mounted.BenchStepNear()
	if not passed then
		return false, `A near-rate run whose halves all drove failed: {reason}`
	elseif eventsOf(mounted.events) ~= table.concat(ORDER, ",") then
		return false, `The near-rate run went {eventsOf(mounted.events)}`
	elseif halvesOf(mounted.asked) ~= HALVES then
		return false, `The near-rate run's halves ran at {halvesOf(mounted.asked)}, not {HALVES}`
	end

	for _, asked: Step.Asked in mounted.asked do
		local name: string = `{asked.scenario}/{asked.half}`
		if asked.workers ~= true or asked.timing ~= mounted.Config.step.timing then
			return false, `{name} was asked for with workers {asked.workers} and its own timing`
		elseif Step.asked(asked) ~= CAPS or asked.split or asked.memory then
			return false, `{name} ran with the caps {Step.asked(asked)}, the split or verdict memory otherwise`
		elseif asked.bands ~= 3 or not asked.crowd or not asked.lazy or not asked.checks then
			return false, `{name} ran with a lever of session 1 or 2 otherwise than the server has it`
		end
	end

	for index: number = 4, #mounted.events do
		local event: string = mounted.events[index]
		if string.find(event, " table, figure: ", 1, true) and not string.find(event, MARKED, 1, true) then
			return false, `A table's columns read otherwise than before then after:\n{event}`
		end
	end

	if AntiEsp.nearRate() ~= SERVER_RATE or AntiEsp.workersOn() then
		return false, `The run left the near rate at {AntiEsp.nearRate()} Hz and the workers {AntiEsp.workersOn()}`
	elseif Step.caps(mounted) ~= CAPS then
		return false, `The run left the caps {Step.caps(mounted)}`
	end

	-- 3) The header: its title and date, the server, the build's notes with both near rates, and the levers once as
	-- the run found them, with no half's line
	local header: string = mounted.events[1]
	local date: string? = string.match(string.sub(header, #TITLE + 1), DATE)
	local rest: string = `{SERVER}; {NOTES}; {FOUND}{LEVERS}`
	if string.sub(header, 1, #TITLE) ~= TITLE or date == nil then
		return false, `The near-rate run's header opened:\n{header}`
	elseif string.sub(header, #TITLE + #date + #" UTC, " + 1) ~= rest then
		return false, `The near-rate run's header read:\n{header}\nnot, after its date:\n{rest}`
	end

	-- 4) No other run flips the raised rate: every half each asks for runs at the server's, and it stays so after
	local other: Step.Mounted = Step.load(answers(nil))
	local runs: { [string]: () -> (boolean, string | nil) } = {
		step = function (): (boolean, string | nil)
			return other.BenchStep()
		end,
		noise = other.BenchStepNoise,
		memory = function (): (boolean, string | nil)
			return other.BenchStep("memory")
		end,
		split = other.BenchStepSplit,
		npcs = other.BenchStepNpcs,
		levers = other.BenchStepLevers,
	}

	for run: string, start: () -> (boolean, string | nil) in runs do
		table.clear(other.asked)
		start()

		if #other.asked == 0 then
			return false, `The {run} run asked for no half`
		elseif other.AntiEsp.nearRate() ~= SERVER_RATE then
			return false, `The {run} run left the near rate at {other.AntiEsp.nearRate()} Hz`
		end

		for _, asked: Step.Asked in other.asked do
			if asked.nearRate ~= SERVER_RATE then
				return false, `The {run} run's {asked.scenario}/{asked.half} ran at {asked.nearRate} Hz`
			end
		end
	end

	-- 5) Started with the workers on, the halves still run as held, and the workers are put back on
	local opposite: Step.Mounted = Step.load(answers(nil))
	opposite.AntiEsp.useWorkers(true)
	opposite.BenchStepNear()

	if halvesOf(opposite.asked) ~= HALVES then
		return false, `Started with the workers on, the halves ran at {halvesOf(opposite.asked)}`
	elseif not opposite.AntiEsp.workersOn() or opposite.AntiEsp.nearRate() ~= SERVER_RATE then
		return false, `Started with the workers on, the run left them {opposite.AntiEsp.workersOn()}`
	end

	-- 6) A half that throws, the third, at the raised rate with the workers held on: the rest still run, the run fails
	-- naming it, and the rate and the workers are put back
	local thrown: Step.Mounted = Step.load(answers(3))
	local threw: boolean, why: string? = thrown.BenchStepNear()
	if threw then
		return false, "A near-rate run whose third half threw passed"
	elseif not string.find(why or "", "Bots S3/after: it threw: a stand-in throw", 1, true) then
		return false, `A near-rate run whose third half threw gave:\n{why}`
	elseif halvesOf(thrown.asked) ~= HALVES then
		return false, `With its third half thrown, the halves ran at {halvesOf(thrown.asked)}`
	elseif thrown.AntiEsp.nearRate() ~= SERVER_RATE or thrown.AntiEsp.workersOn() then
		local workers: boolean = thrown.AntiEsp.workersOn()
		return false, `After a thrown half, the near rate stood {thrown.AntiEsp.nearRate()} Hz, the workers {workers}`
	end

	-- And a table that throws past the halves, on a run started with the workers on, after the first load held them
	-- off: the run fails naming the throw, the workers are put back on and the rate back to the server's
	local broken: Step.Mounted = Step.load(function (): (boolean, string, { [string]: number }?)
		return true, "drove and cleaned up", { skipped = "many" :: any }
	end)

	broken.AntiEsp.useWorkers(true)
	local tabled: boolean, tableWhy: string? = broken.BenchStepNear()
	if tabled then
		return false, "A near-rate run whose table threw passed"
	elseif not string.find(tableWhy or "", "Step benchmark near rate run threw: ", 1, true) then
		return false, `A near-rate run whose table threw gave:\n{tableWhy}`
	elseif #broken.asked ~= 2 then
		return false, `A near-rate run whose first table threw asked for {#broken.asked} halves, not 2`
	elseif not broken.AntiEsp.workersOn() or broken.AntiEsp.nearRate() ~= SERVER_RATE then
		return false, `After a thrown table, the workers stood {broken.AntiEsp.workersOn()}`
	end

	-- 7) A hold refused: the run fails naming each refusal, at the hold and at the restore, while the halves still run
	-- and both tables print
	local refusing: Step.Mounted = Step.load(answers(nil))
	leverOf(refusing.Levers, WORKERS).set = function (_: boolean)
		error(REFUSAL, 0)
	end

	local held: boolean, heldWhy: string? = refusing.BenchStepNear()
	local named: string = `Step benchmark near rate run's levers refused: {WORKERS} refused off: {REFUSAL}, `
		.. `{WORKERS} refused on: {REFUSAL}, {WORKERS} refused off: {REFUSAL}`
	if held then
		return false, "A near-rate run whose hold was refused passed"
	elseif not string.find(heldWhy or "", named, 1, true) then
		return false, `A near-rate run whose hold was refused gave:\n{heldWhy}`
	elseif #refusing.asked ~= 4 or eventsOf(refusing.events) ~= table.concat(ORDER, ",") then
		return false, `A near-rate run whose hold was refused went {eventsOf(refusing.events)}`
	end

	-- 8) The off side is the server's own rate as its settings give it, in the before halves, the note and the restore
	local changed: Step.Mounted = Step.load(answers(nil))
	changed.settings.antiEsp.nearRate = OTHER_RATE
	changed.BenchStepNear()

	local note: string = `and off at the server's antiEsp.nearRate of {OTHER_RATE} Hz; `
	if halvesOf(changed.asked) ~= OTHER_HALVES then
		return false, `With the server's rate at {OTHER_RATE} Hz, the halves ran at {halvesOf(changed.asked)}`
	elseif not string.find(changed.events[1], note, 1, true) then
		return false, `With the server's rate at {OTHER_RATE} Hz, the header read:\n{changed.events[1]}`
	elseif changed.AntiEsp.nearRate() ~= OTHER_RATE then
		return false, `With the server's rate at {OTHER_RATE} Hz, the run left it at {changed.AntiEsp.nearRate()} Hz`
	end

	return true, nil
end
