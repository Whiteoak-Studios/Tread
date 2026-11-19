--[[
    A live arm program runs the dev place's ParallelProbe after its last run
    only when its program says so, A0's quick but not full or A1's, and the
    report gets the probe's lines, then its verdict, before the last line
--]]

--!strict
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox: any = require("@lune/roblox") -- Its typedefs leave out the datatypes
local task = require("@lune/task")

local A0_CONFIG: string = "dev/Arms/A0/Config.luau"
local A1_CONFIG: string = "dev/Arms/A1/Config.luau"
local TYPES: string = "dev/Arms/A0/Shared/Types.luau"
local PROGRAM: string = "dev/Arms/A0/Server/Program.luau"
local DATATYPE: string = "^%u" -- A name Lune's library holds a Roblox datatype, Enum or Instance under
local SHORT_WAIT: number = 0.05 -- The lost verdict's outputWait, so its deadline passes within the case
local PROBE_EVENT: string = "probe" -- What the probe's call adds to the run's events, beside each run's label

-- What the stand-in probe prints, its reason when it fails and its error when it throws
local COUNT_LINE: string = "ParallelProbe 1 worker: 50 of 50 batches"
local WARNING: string = "a worker warned"
local SUMMARY_LINE: string = "ParallelProbe summary: serial loop p50 2.000 ms at 47 passes"
local REASON: string = "2 workers stopped short"
local THROWN: string = "the probe broke"

local PASSED: string = "A0 ParallelProbe: passed"
local QUICK_DONE: string = "A0 program quick: every run has finished"

-- One live program: its config file, the program set in it, what the probe does, and what the run gives
type Case = {
	config: string,
	program: string?, -- Set in the config before Program loads, nil keeping the config's own
	probe: string, -- "passes", "fails" after a warning, or "throws" after its first line
	lost: boolean, -- Whether the verdict's print never reaches the Output
	measured: number, -- Runs handed to Run.measure
	probed: boolean,
	report: { string }, -- The report's lines after the opening
}

local CASES: { Case } = {
	{
		config = A0_CONFIG,
		probe = "passes",
		lost = false,
		measured = 4,
		probed = true,
		report = { COUNT_LINE, SUMMARY_LINE, PASSED, QUICK_DONE },
	},

	{
		config = A0_CONFIG,
		probe = "fails",
		lost = false,
		measured = 4,
		probed = true,
		report = {
			COUNT_LINE,
			`MessageWarning: {WARNING}`,
			SUMMARY_LINE,
			`A0 ParallelProbe: failed: {REASON}`,
			QUICK_DONE,
		},
	},

	{
		config = A0_CONFIG,
		probe = "throws",
		lost = false,
		measured = 4,
		probed = true,
		report = { COUNT_LINE, `A0 ParallelProbe: threw: {THROWN}`, QUICK_DONE },
	},

	{
		config = A0_CONFIG,
		probe = "passes",
		lost = true,
		measured = 4,
		probed = true,
		report = {
			COUNT_LINE,
			SUMMARY_LINE,
			`A0 ParallelProbe: its verdict line was not back through the Output within {SHORT_WAIT} s`,
			PASSED,
			QUICK_DONE,
		},
	},

	{
		config = A0_CONFIG,
		program = "full",
		probe = "passes",
		lost = false,
		measured = 12,
		probed = false,
		report = { "A0 program full: every run has finished" },
	},

	{
		config = A1_CONFIG,
		probe = "passes",
		lost = false,
		measured = 6,
		probed = false,
		report = { "A1 program full: every run has finished" },
	},
}

local function child(className: string, name: string, parent: any): any
	local made: any = roblox.Instance.new(className)
	made.Name = name
	made.Parent = parent

	return made
end

-- Requires each module of the files once, with script set to it and the scope's game, task, print and datatypes
local function loader(scope: { [string]: any }, files: { [any]: string }, results: { [any]: any }): (target: any) -> any
	local function load(target: any): any
		local result: any = results[target]
		if result ~= nil then
			return result
		end

		local path: string = files[target]
		local environment: { [string]: any } = table.clone(scope)
		environment.script = target
		environment.require = load

		local chunk: () -> any = luau.load(fs.readFile(path), { debugName = path, environment = environment })
		results[target] = chunk()

		return results[target]
	end

	return load
end

--[[
    Runs Program.all on a fresh game with one player in, every run and the
    probe stood in for, every wait a frame long, and an Output that reaches
    its listeners a frame late, then checks what the case expects
--]]

local function check(case: Case, index: number): (boolean, string?)
	local dataModel: any = roblox.Instance.new("DataModel")
	local workspace: any = dataModel:GetService("Workspace")
	local serverScripts: any = dataModel:GetService("ServerScriptService")
	local output: any = roblox.Enum.MessageType.MessageOutput

	local events: { string } = {}
	local report: { string } = {}
	local listeners: { (string, any) -> () } = {}
	local connects: number = 0
	local doneAtProbe: any = nil
	local done: string = ""

	local function emit(line: string, kind: any)
		task.defer(function ()
			for _, listener: (string, any) -> () in table.clone(listeners) do
				listener(line, kind)
			end
		end)
	end

	local logService: { [string]: any } = {
		MessageOut = {
			Connect = function (_: any, listener: (string, any) -> ()): any
				connects += 1
				table.insert(listeners, listener)

				return {
					Disconnect = function (_: any)
						local at: number? = table.find(listeners, listener)
						if at then
							table.remove(listeners, at)
						end
					end,
				}
			end,
		},
	}

	local players: { [string]: any } = {
		GetPlayers = function (_: any): { any }
			return { {} }
		end,
	}

	local fakes: { [string]: any } = { LogService = logService, Players = players }
	local scope: { [string]: any } = {
		game = {
			GetService = function (_: any, name: string): any
				return fakes[name] or dataModel:GetService(name)
			end,
		},

		task = {
			wait = function (_: number?)
				task.wait()
			end,
		},

		print = function (message: string)
			if not case.lost then
				emit(message, output)
			end
		end,
	}

	for name: string, value: any in roblox do
		if name:match(DATATYPE) then
			scope[name] = value
		end
	end

	-- The probe as the dev place's prints its lines, a count's, then its summary, before it returns
	local function probe(): (boolean, string?)
		table.insert(events, PROBE_EVENT)
		doneAtProbe = workspace:GetAttribute(done)

		emit(COUNT_LINE, output)
		if case.probe == "throws" then
			error(THROWN, 0)
		elseif case.probe == "fails" then
			emit(WARNING, roblox.Enum.MessageType.MessageWarning)
		end

		emit(SUMMARY_LINE, output)
		if case.probe == "fails" then
			return false, REASON
		end

		return true, nil
	end

	local run: { [string]: any } = {
		measure = function (label: string, _: any, _: any): (boolean, string)
			table.insert(events, label)
			return true, label
		end,

		record = function (line: string)
			table.insert(report, line)
		end,
	}

	-- The arm's modules where its project file puts them, and the probe where the dev place has it
	local shared: any = child("Folder", "Arm", dataModel:GetService("ReplicatedStorage"))
	local arm: any = child("Folder", "Arm", serverScripts)
	local scenarios: any = child("Folder", "Scenarios", child("Folder", "Server", serverScripts))
	local config: any = child("ModuleScript", "Config", shared)
	local types: any = child("ModuleScript", "Types", shared)
	local program: any = child("ModuleScript", "Program", arm)
	local bots: any = child("ModuleScript", "Bots", arm)
	local runner: any = child("ModuleScript", "Run", arm)
	local parallelProbe: any = child("ModuleScript", "ParallelProbe", scenarios)

	local files: { [any]: string } = { [config] = case.config, [types] = TYPES, [program] = PROGRAM }
	local results: { [any]: any } = { [bots] = {}, [runner] = run, [parallelProbe] = probe }
	local load: (target: any) -> any = loader(scope, files, results)

	local Config: any = load(config)
	done = Config.doneAttribute
	if case.program then
		Config.program = case.program
	end

	if case.lost then
		Config.outputWait = SHORT_WAIT
	end

	load(program).all({})

	local label: string = `Program.all case {index}`
	local probes: number = 0
	for _, event: string in events do
		if event == PROBE_EVENT then
			probes += 1
		end
	end

	-- 1) The probe runs once, after every run, or not at all
	local expected: number = case.probed and 1 or 0
	if probes ~= expected or #events ~= case.measured + expected then
		local counted: string = `measured {#events - probes} runs and probed {probes} times`
		return false, `{label} {counted}, not {case.measured} and {expected}`
	elseif case.probed and events[#events] ~= PROBE_EVENT then
		return false, `{label} ran the probe before its last run`
	end

	-- 2) The program is marked done only after the probe, and the probe's Output listener is gone
	if case.probed and doneAtProbe ~= nil then
		return false, `{label} was marked done before the probe ran`
	elseif workspace:GetAttribute(done) ~= true then
		return false, `{label} was never marked done`
	elseif connects ~= expected or #listeners > 0 then
		return false, `{label} connected {connects} Output listeners and left {#listeners} connected`
	end

	-- 3) After the opening, the report holds the probe's lines in order, its verdict, then the program's last line
	if #report ~= #case.report + 1 then
		return false, `{label} recorded {#report} lines, not the opening and {#case.report}`
	end

	for line: number, wanted: string in case.report do
		local got: string = report[line + 1]
		if got ~= wanted then
			return false, `{label} recorded "{got}" as line {line + 1}, not "{wanted}"`
		end
	end

	return true, nil
end

return function (): (boolean, string | nil)
	for index: number, case: Case in CASES do
		local passed: boolean, reason: string? = check(case, index)
		if not passed then
			return false, reason
		end
	end

	return true, nil
end
