--[[
    The step benchmark: S4's fight and the two spread loads, each run as a
    half with the session's new levers off and one with them on, or one of
    its kinds, a noise run or a run that flips one lever alone each load
--]]

--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Tread = require(ReplicatedStorage.Packages.Tread)

local Compare = require(ServerScriptService.Server.Bots.Compare)
local Config = require(ServerScriptService.Server.Bots.Config)
local Game = require(ServerScriptService.Server.Game)
local Levers = require(ServerScriptService.Server.Bots.Levers)
local Run = require(ServerScriptService.Server.Bots.Run)

local LOADS: { Config.StepLoad } = require(ServerScriptService.Server.Bots.Config).step.loads
local MEMORY: Config.StepLoad = require(ServerScriptService.Server.Bots.Config).step.memory
local NPCS: Config.StepLoad = require(ServerScriptService.Server.Bots.Config).step.npcs
local LEVER_LOADS: { Config.StepLoad } = require(ServerScriptService.Server.Bots.Config).step.levers
local NEAR: Config.StepLoad = require(ServerScriptService.Server.Bots.Config).step.near
local TIMING: Config.Timing = require(ServerScriptService.Server.Bots.Config).step.timing
local SESSION: number = require(ServerScriptService.Server.Bots.Config).step.session
local HALVES: { string } = { "before", "after" } -- What the halves with the levers off and on are called
local NOISE: { string } = { "first", "second" } -- What the noise run's halves are called, in the order they run
local COLUMNS: { boolean } = { false, true } -- The halves' levers in the order the table's columns take them
local MEMORY_LEVER: string = "verdictMemory" -- The one lever the memory run's halves flip, by its name
local SPLIT_LEVER: string = "stageSplit" -- The split run's
local NPC_LEVER: string = "npcBudget" -- The NPC budget run's
local TITLE: string = "Step benchmark"
local NOISE_TITLE: string = "Step benchmark noise run"
local MEMORY_TITLE: string = "Step benchmark verdict memory run"
local SPLIT_TITLE: string = "Step benchmark split run"
local NPCS_TITLE: string = "Step benchmark NPC budget run"
local LEVERS_TITLE: string = "Step benchmark levers run"
local NEAR_TITLE: string = "Step benchmark near rate run"
local HELD: string = "held for the run, each load's own lever off before and on after" -- The levers run's one part
local DATE: string = "!%Y-%m-%d" -- The UTC date, as the header names it
local SEPARATOR: string = "; " -- Between the header's parts, and between the halves' lines
local COMMA: string = ", " -- Between the refusals a half's levers gave
local NO_POOL: string = "no anti-ESP workers made, so every ray is cast in process however antiEspWorkers reads"
local SHOWN: string = "%.1f tests answered from memory and %.1f rays a kept box blocked a tick at p50" -- As its table rows

-- What the header says of the build every run of the session measures, and what the split run's halves read
local CLOCK_NOTE: string = "the worker clock's unpack section holds each worker's read of its own hand-in"
local CARRY_NOTE: string = "with relayBudget on, a viewer's turn after a run that left it can carry that run's "
	.. "footsteps, which raises the bytes rows and leaves the records rows alone"
local SPLIT_NOTE: string = "with stageSplit on, the frame holding a tick holds frame 1 alone, the relay's dispatch "
	.. "moves to the Heartbeat after and the bots' stage to the one after that"
local NEAR_NOTE: string = "anti-ESP retests each near hidden pair once a server tick, at the first slice after the bodies "
	.. "step" -- And the near rate run's

type Figures = Compare.Figures

-- The step benchmark's runs besides its own: the noise run, and those that flip one lever alone a load
export type Kind = "noise" | "memory" | "split" | "npcs" | "levers" | "near"

-- What a kind of run is called
local function titleOf(kind: Kind?): string
	if kind == "noise" then
		return NOISE_TITLE
	elseif kind == "memory" then
		return MEMORY_TITLE
	elseif kind == "split" then
		return SPLIT_TITLE
	elseif kind == "npcs" then
		return NPCS_TITLE
	elseif kind == "levers" then
		return LEVERS_TITLE
	elseif kind == "near" then
		return NEAR_TITLE
	end

	return TITLE
end

-- A kind of run's loads, in the order they run, and what its halves are called
local function loadsOf(kind: Kind?): ({ Config.StepLoad }, { string })
	if kind == "noise" then
		return LOADS, NOISE
	elseif kind == "memory" then
		return { MEMORY }, HALVES
	elseif kind == "npcs" then
		return { NPCS }, HALVES
	elseif kind == "levers" then
		return LEVER_LOADS, HALVES
	elseif kind == "near" then
		return { NEAR }, HALVES
	end

	return LOADS, HALVES
end

-- What a half is called and the state its levers are set to, nil for the noise run's, whose run sets them once
local function named(kind: Kind?, place: number, on: boolean): (string, boolean?)
	if kind == "noise" then
		return NOISE[place], nil
	end

	return on and HALVES[2] or HALVES[1], on
end

-- Adds every refusal of one list to another
local function addAll(refused: { string }, more: { string })
	table.move(more, 1, #more, #refused + 1, refused)
end

-- Adds each state a flip found to the states but for a lever they already name, so each keeps the first state found
local function addFirst(states: { [string]: boolean }, found: { [string]: boolean })
	for name: string, state: boolean in found do
		if states[name] == nil then
			states[name] = state
		end
	end
end

--[[
    Sets a half's levers as on says: the one lever its load names, or its
    kind's one, by that name, and otherwise every lever of the session but
    those marked alone
--]]

local function flipped(kind: Kind?, load: Config.StepLoad, on: boolean): ({ [string]: boolean }, { string })
	local lever: string? = load.lever
	if kind == "memory" then
		lever = MEMORY_LEVER
	elseif kind == "split" then
		lever = SPLIT_LEVER
	elseif kind == "npcs" then
		lever = NPC_LEVER
	end

	return Levers.flip(SESSION, on, lever)
end

--[[
    The levers run's hold: the session's levers off, and each lever its
    loads flip off too, by its name, giving the state each was in before,
    as the first flip that set it found it, and every refusal
--]]

local function held(): ({ [string]: boolean }, { string })
	local states: { [string]: boolean }, refused: { string } = Levers.flip(SESSION, false)

	for _, load: Config.StepLoad in LEVER_LOADS do
		local found: { [string]: boolean }, refusals: { string } = Levers.flip(SESSION, false, load.lever)
		addAll(refused, refusals)
		addFirst(states, found)
	end

	return states, refused
end

--[[
    The levers' line as they stand in a half, set there and put back at
    once, with any refusal either gave. A line that throws is thrown again
    once the levers are back
--]]

local function leversIn(kind: Kind?, load: Config.StepLoad, on: boolean?): string
	local states: { [string]: boolean } = {}
	local refused: { string } = {}
	if on ~= nil then
		states, refused = flipped(kind, load, on)
	end

	local read: boolean, line: any = pcall(Levers.line)
	addAll(refused, Levers.restore(states))

	if not read then
		error(line, 0)
	elseif #refused > 0 then
		return `{line}, and refused: {table.concat(refused, COMMA)}`
	end

	return line
end

--[[
    The header: the run and its session, the UTC date, the place's version
    and the server's job, the real players in, the relay workers started,
    the anti-ESP workers made, what the session's build changes in how the
    rows read, how the near rate run's pairs are retested, and every
    lever as it stands in each half, or once as the levers run holds them
--]]

local function header(kind: Kind?, load: Config.StepLoad): string
	local levers: { string } = {}
	if kind == "levers" then
		table.insert(levers, `{HELD}: {leversIn(kind, load, nil)}`)
	else
		for place: number, on: boolean in COLUMNS do
			local name: string, flip: boolean? = named(kind, place, on)
			table.insert(levers, `{name}: {leversIn(kind, load, flip)}`)
		end
	end

	local _, _, settings: Tread.ServerSettings = Game.get()
	local notes: { string } = { CLOCK_NOTE, CARRY_NOTE }
	if kind == "split" then
		table.insert(notes, SPLIT_NOTE)
	elseif kind == "near" then
		table.insert(notes, NEAR_NOTE)
	end

	local made: number = settings.antiEsp.workers or 0
	local antiEsp: string = `{made} anti-ESP workers made`
	if made == 0 then
		antiEsp = NO_POOL
	end

	local date: string = os.date(DATE)
	local server: string = `place version {game.PlaceVersion}, job {game.JobId}`
	local workers: string = `{Run.workers()} relay workers started, {antiEsp}`
	local players: string = `{#Players:GetPlayers()} real players in, {workers}`
	local parts: string = `{table.concat(notes, SEPARATOR)}{SEPARATOR}{table.concat(levers, SEPARATOR)}`

	return `{titleOf(kind)} session {SESSION}, {date} UTC, {server}, {players}; {parts}`
end

--[[
    One half: its levers set as on says, or none when it is nil, the load
    run under the half's name with the relay's workers, and the levers put
    back whatever the run did. A half that fails or throws gives no
    figures, and one whose levers refused keeps its figures and fails,
    naming each refusal, since it ran as neither half, and says so last
--]]

local function half(
	kind: Kind?,
	load: Config.StepLoad,
	name: string,
	on: boolean?
): (boolean, string, Figures?, boolean)
	local scenario: string = load.scenario
	local states: { [string]: boolean } = {}
	local refused: { string } = {}
	if on ~= nil then
		states, refused = flipped(kind, load, on)
	end

	local ran: boolean, passed: any, line: any, figures: any = pcall(Run.runWorkers, scenario, TIMING, true, nil, name)
	addAll(refused, Levers.restore(states))

	local ok: boolean, text: string, carried: Figures? = true, tostring(line), figures
	if not ran then
		ok, text, carried = false, `Bots {scenario}/{name}: it threw: {passed}`, nil
	elseif passed ~= true then
		ok, carried = false, nil
	end

	if #refused > 0 then
		return false,
			`{text}{SEPARATOR}Bots {scenario}/{name}'s levers refused: {table.concat(refused, COMMA)}`,
			carried,
			true
	end

	return ok, text, carried, false
end

-- Whether a half's figures show verdict memory at work: a test answered from memory or a ray a kept box blocked
local function remembered(figures: Figures): boolean
	return (figures.antiEspKept or 0) > 0 or (figures.antiEspBoxRays or 0) > 0
end

--[[
    Why a memory run's halves show it measured nothing, one line each: an
    after half that shows neither of verdict memory's counts above 0, and a
    before half, with memory off, that shows either. A half that is nil,
    having no figures or having had its levers refused, already failed and
    gives none
--]]

local function unshown(scenario: string, before: Figures?, after: Figures?): { string }
	local problems: { string } = {}
	if after and not remembered(after) then
		local counts: string = "no test answered from memory and no ray a kept box blocked"
		table.insert(problems, `Bots {scenario}/{HALVES[2]}: verdict memory showed {counts}, so the run showed nothing`)
	end

	if before and remembered(before) then
		local tests: number, rays: number = before.antiEspKept or 0, before.antiEspBoxRays or 0
		local counts: string = string.format(SHOWN, tests, rays)
		table.insert(problems, `Bots {scenario}/{HALVES[1]}: with verdict memory off, it showed {counts}`)
	end

	return problems
end

--[[
    The header, then each load's two halves in the configured order and its
    table once both are done, titled by the load and any lever it flips,
    and for the memory run its halves' check, with a line for each half and
    each problem. A half that fails reads missing in its table while the
    rest still run. It gives whether every half drove and cleaned up with
    its levers set as it asked
--]]

local function runLoads(kind: Kind?, lines: { string }): boolean
	local loads: { Config.StepLoad }, names: { string } = loadsOf(kind)
	local passed: boolean = true
	print(header(kind, loads[1]))

	for _, load: Config.StepLoad in loads do
		local figures: { [string]: Figures } = {} -- Each half's that drove, by its name
		local judged: { [string]: Figures } = {} -- Those of the halves whose levers were set as they asked

		for place: number, on: boolean in load.order do
			local name: string, flip: boolean? = named(kind, place, on)
			local ok: boolean, line: string, carried: Figures?, refused: boolean = half(kind, load, name, flip)
			passed = passed and ok
			table.insert(lines, line)

			if carried then
				figures[name] = carried
			end

			if carried and not refused then
				judged[name] = carried
			end
		end

		local title: string = load.scenario
		if load.lever then
			title = `{load.scenario} {load.lever}`
		end

		print(Compare.table(title, names, figures[names[1]], figures[names[2]]))

		if kind == "memory" then
			local problems: { string } = unshown(load.scenario, judged[HALVES[1]], judged[HALVES[2]])
			passed = passed and #problems == 0
			addAll(lines, problems)
		end
	end

	return passed
end

--[[
    Runs the step benchmark, or the kind of run given. The noise run sets
    the session's levers on before its first half and the levers run holds
    them off with each lever its loads flip, and each puts back what it
    found after its last, however the run ended. A throw anywhere in the
    run fails it with a line naming the throw. It passes only when every
    half drove and cleaned up with its levers set as it asked, every hold
    was set, and in the memory run its after half showed verdict memory and
    its before half didn't
--]]

return function (kind: Kind?): (boolean, string | nil)
	local lines: { string } = {}

	-- So both of the noise run's halves run as an after half does, with no flip between them, and the levers run's
	-- halves differ by their load's lever alone
	local states: { [string]: boolean } = {}
	local refused: { string } = {}
	if kind == "noise" then
		states, refused = Levers.flip(SESSION, true)
	elseif kind == "levers" then
		states, refused = held()
	end

	local ran: boolean, result: any = pcall(runLoads, kind, lines)
	addAll(refused, Levers.restore(states))

	local passed: boolean = ran and result == true
	if not ran then
		table.insert(lines, `{titleOf(kind)} threw: {result}`)
	end

	if #refused > 0 then
		passed = false
		table.insert(lines, `{titleOf(kind)}'s levers refused: {table.concat(refused, COMMA)}`)
	end

	return passed, table.concat(lines, SEPARATOR)
end
