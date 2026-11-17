--[[
    The arm's runs by scenario and seed: one started from execute_luau in
    Studio, or the configured program's runs in turn on a live server, and
    after them the dev place's ParallelProbe when the program runs it
--]]

--!strict
local LogService = game:GetService("LogService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local Bots = require(ServerScriptService.Arm.Bots)
local Config = require(ReplicatedStorage.Arm.Config)
local ParallelProbe = require(ServerScriptService.Server.Scenarios.ParallelProbe)
local Run = require(ServerScriptService.Arm.Run)

local ARM: string = Config.arm
local PROGRAM: string = Config.program
local DONE_ATTRIBUTE: string = Config.doneAttribute
local LIVE_JOIN_TIMEOUT: number = Config.liveJoinTimeout
local POLL_INTERVAL: number = Config.pollInterval
local OUTPUT_WAIT: number = Config.outputWait
local PROBE: string = `{ARM} ParallelProbe` -- What the probe's verdict line begins with
local TEST_CONTENT: string = "TestContent" -- The dev place's folder of test content, kept by a copy pasted here
local CITY_BLOCK: string = "CityBlock" -- The city block in it, which S3's city bots walk among
local SEPARATOR: string = "; " -- Between the figures of one report line
local LIST: string = ", " -- Between the entries of one figure

local Types = require(ReplicatedStorage.Arm.Types)

type Load = Types.Load
type Program = Types.Program
type Scenario = Types.Scenario

local Program = {}

--[[
    The program whose timing a scenario runs on: the configured one when it
    lists the scenario, else another that does, or nil when none does
--]]

local function programFor(scenario: string): Program?
	local configured: Program? = Config.programs[PROGRAM]
	if configured and table.find(configured.scenarios, scenario) then
		return configured
	end

	for _, program: Program in Config.programs do
		if table.find(program.scenarios, scenario) then
			return program
		end
	end

	return nil
end

--[[
    A run's label, the load that starts its scenario for its seed and the
    program it times by, or no load when no scenario or program has the
    name or the seed is not a number
--]]

local function resolve(scenario: string, seed: number): (string, Load?, Program?)
	local label: string = `{ARM} {scenario} seed {seed}`

	local found: Scenario? = Config.scenarios[scenario]
	local program: Program? = programFor(scenario)
	if not found or not program or type(seed) ~= "number" then
		return label, nil, nil
	end

	local spec: Scenario = found
	return label, function ()
		return Bots.start(spec, seed)
	end, program
end

--[[
    Starts one run and answers at once, for an execute_luau chunk:
    Program.start("S2", 1) returns true and when its line will be ready,
    or false and why it was refused
--]]

function Program.start(scenario: string, seed: number): (boolean, string)
	local label: string, load: Load?, program: Program? = resolve(scenario, seed)
	if not load or not program then
		return false, `{label}: no scenario or program has that name, or the seed is not a number`
	end

	return Run.start(label, load, program)
end

--[[
    Runs one run to its end and returns its line, which is in the report too
--]]

function Program.run(scenario: string, seed: number): (boolean, string)
	local label: string, load: Load?, program: Program? = resolve(scenario, seed)
	if not load or not program then
		local line: string = `{label}: no scenario or program has that name, or the seed is not a number`
		Run.record(line)
		return false, line
	end

	return Run.measure(label, load, program)
end

--[[
    The seconds a program waits out from its first player's join to its
    last line: its start delay, each run's warm-up and window, the pauses
    between runs, and the pause before the probe when it runs one. Each
    run's calibration and spawn, and the probe's own work, come on top
--]]

function Program.length(program: Program): number
	local runs: number = #program.scenarios * #program.seeds
	local pauses: number = math.max(runs - 1, 0)
	if program.parallelProbe then
		pauses += 1
	end

	return program.startDelay + runs * (program.warmupSeconds + program.steadySeconds) + pauses * program.pauseSeconds
end

--[[
    The line a live program opens with: the real players, whether the city
    block is in the place, the floors laid at boot, and its runs and waits
--]]

local function opening(program: Program, floors: { string }): string
	local testContent: Instance? = Workspace:FindFirstChild(TEST_CONTENT)
	local city: Instance? = testContent and testContent:FindFirstChild(CITY_BLOCK)
	local runs: number = #program.scenarios * #program.seeds

	local seeds: { string } = {}
	for _, seed: number in program.seeds do
		table.insert(seeds, tostring(seed))
	end

	local parts: { string } = {
		`{ARM} program {PROGRAM}: real players {#Players:GetPlayers()}`,
		`Workspace.{TEST_CONTENT}.{CITY_BLOCK} {city and "present" or "missing"}`,
		`floors laid: {#floors > 0 and table.concat(floors, LIST) or "none"}`,
		`{runs} runs of {table.concat(program.scenarios, LIST)} over seeds {table.concat(seeds, LIST)}`,
		`each a {program.warmupSeconds} s warm-up and a {program.steadySeconds} s window`,
		`about {Program.length(program)} s of waits in all`,
	}

	return table.concat(parts, SEPARATOR)
end

--[[
    Runs the dev place's ParallelProbe and records what the server's Output
    heard while it ran, in order, then its verdict: passed, failed with its
    reason, or threw. The verdict is printed too, since the Output reaches
    the listener frames late and its arrival means every earlier line has
--]]

local function probe()
	local lines: { string } = {}
	local verdict: string? = nil
	local heard: boolean = false

	-- Disconnected below, once the verdict line arrives or the wait for it passes its deadline
	local output: RBXScriptConnection = LogService.MessageOut:Connect(function (message: string, kind: Enum.MessageType)
		if message == verdict then
			heard = true
		elseif not heard then
			table.insert(lines, kind == Enum.MessageType.MessageOutput and message or `{kind.Name}: {message}`)
		end
	end)

	local ran: boolean, passed: any, reason: any = pcall(ParallelProbe)
	local said: string = `{PROBE}: passed`
	if not ran then
		said = `{PROBE}: threw: {passed}`
	elseif passed ~= true then
		said = `{PROBE}: failed: {reason}`
	end

	verdict = said
	print(said)

	local deadline: number = os.clock() + OUTPUT_WAIT
	while not heard and os.clock() < deadline do
		task.wait(POLL_INTERVAL)
	end

	output:Disconnect()

	if not heard then
		table.insert(lines, `{PROBE}: its verdict line was not back through the Output within {OUTPUT_WAIT} s`)
	end

	table.insert(lines, said)

	for _, line: string in lines do
		Run.record(line)
	end
end

--[[
    Records a live program's last line and marks it done, which opens every
    client's panel on the report
--]]

local function finish(line: string)
	Run.record(line)
	Workspace:SetAttribute(DONE_ATTRIBUTE, true)
end

--[[
    Waits for a live server's first real player, gives every other device
    the configured program's start delay to join, then runs each of its
    scenarios for each seed in turn with a pause between runs, and after a
    last pause the probe when the program runs it. The floors are the ones
    laid at boot, which its opening line names
--]]

function Program.all(floors: { string })
	local program: Program? = Config.programs[PROGRAM]
	if not program then
		finish(`{ARM} program {PROGRAM}: no program has that name, so nothing ran`)
		return
	end

	local deadline: number = os.clock() + LIVE_JOIN_TIMEOUT
	while #Players:GetPlayers() == 0 and os.clock() < deadline do
		task.wait(POLL_INTERVAL)
	end

	if #Players:GetPlayers() == 0 then
		finish(`{ARM} program {PROGRAM}: no player joined within {LIVE_JOIN_TIMEOUT} s, so nothing ran`)
		return
	end

	task.wait(program.startDelay)
	Run.record(opening(program, floors))

	local runs: number = 0
	for _, scenario: string in program.scenarios do
		for _, seed: number in program.seeds do
			if runs > 0 then
				task.wait(program.pauseSeconds)
			end

			runs += 1
			Program.run(scenario, seed)
		end
	end

	-- Every run's bots are gone, and the pause lets the last run's lines reach the Output before the probe listens
	if program.parallelProbe then
		task.wait(program.pauseSeconds)
		probe()
	end

	finish(`{ARM} program {PROGRAM}: every run has finished`)
end

return Program
