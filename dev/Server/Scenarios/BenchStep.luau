--[[
    The step benchmark: S4's fight and the two spread loads, each run as a
    half with the session's new levers off and one with them on, or twice
    with none flipped for its noise run, each load closing on its table
--]]

--!strict
local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")

local Compare = require(ServerScriptService.Server.Bots.Compare)
local Config = require(ServerScriptService.Server.Bots.Config)
local Levers = require(ServerScriptService.Server.Bots.Levers)
local Run = require(ServerScriptService.Server.Bots.Run)

local LOADS: { Config.StepLoad } = require(ServerScriptService.Server.Bots.Config).step.loads
local TIMING: Config.Timing = require(ServerScriptService.Server.Bots.Config).step.timing
local SESSION: number = require(ServerScriptService.Server.Bots.Config).step.session
local HALVES: { string } = { "before", "after" } -- What the halves with the levers off and on are called
local NOISE: { string } = { "first", "second" } -- What the noise run's halves are called, in the order they run
local COLUMNS: { boolean } = { false, true } -- The halves' levers in the order the table's columns take them
local TITLE: string = "Step benchmark"
local NOISE_TITLE: string = "Step benchmark noise run"
local DATE: string = "!%Y-%m-%d" -- The UTC date, as the header names it
local SEPARATOR: string = "; " -- Between the header's parts, and between the halves' lines

type Figures = Compare.Figures

-- What a half is called and the state its levers are set to, nil for the noise run's, which flips none
local function named(noise: boolean, place: number, on: boolean): (string, boolean?)
	if noise then
		return NOISE[place], nil
	end

	return on and HALVES[2] or HALVES[1], on
end

-- The levers' line as they stand in a half, set there and put back at once
local function leversIn(on: boolean?): string
	local states: { [string]: boolean } = {}
	if on ~= nil then
		states = Levers.flip(SESSION, on)
	end

	local line: string = Levers.line()
	Levers.restore(states)

	return line
end

--[[
    The header: the run and its session, the UTC date, the place's version
    and the server's job, the real players in, the relay workers started,
    and every lever as it stands in each half
--]]

local function header(noise: boolean): string
	local levers: { string } = {}
	for place: number, on: boolean in COLUMNS do
		local name: string, flip: boolean? = named(noise, place, on)
		table.insert(levers, `{name}: {leversIn(flip)}`)
	end

	local title: string = noise and NOISE_TITLE or TITLE
	local date: string = os.date(DATE)
	local server: string = `place version {game.PlaceVersion}, job {game.JobId}`
	local players: string = `{#Players:GetPlayers()} real players in, {Run.workers()} relay workers started`

	return `{title} session {SESSION}, {date} UTC, {server}, {players}; {table.concat(levers, SEPARATOR)}`
end

--[[
    One half: the session's levers set as on says, or none when it is nil,
    the load run under the half's name with the relay's workers, and the
    levers put back whatever the run did. A half that fails or throws
    gives no figures
--]]

local function half(scenario: string, name: string, on: boolean?): (boolean, string, Figures?)
	local states: { [string]: boolean } = {}
	if on ~= nil then
		states = Levers.flip(SESSION, on)
	end

	local ran: boolean, passed: any, line: any, figures: any = pcall(Run.runWorkers, scenario, TIMING, true, nil, name)
	Levers.restore(states)

	if not ran then
		return false, `Bots {scenario}/{name}: it threw: {passed}`, nil
	elseif passed ~= true then
		return false, tostring(line), nil
	end

	return true, tostring(line), figures
end

--[[
    Runs the step benchmark, or its noise run when noise is true: the
    header, then each load's two halves in the configured order, the noise
    run's with no lever flipped, and the load's table once both are done. A
    half that fails reads missing in its table while the rest still run,
    and the run passes only when every half drove and cleaned up
--]]

return function (noise: boolean?): (boolean, string | nil)
	local quiet: boolean = noise == true
	local names: { string } = quiet and NOISE or HALVES
	local passed: boolean = true
	local lines: { string } = {}

	print(header(quiet))

	for _, load: Config.StepLoad in LOADS do
		local figures: { [string]: Figures } = {} -- Each half's that drove, by its name

		for place: number, on: boolean in load.order do
			local name: string, flip: boolean? = named(quiet, place, on)
			local ok: boolean, line: string, carried: Figures? = half(load.scenario, name, flip)
			passed = passed and ok
			table.insert(lines, line)

			if carried then
				figures[name] = carried
			end
		end

		print(Compare.table(load.scenario, names, figures[names[1]], figures[names[2]]))
	end

	return passed, table.concat(lines, SEPARATOR)
end
