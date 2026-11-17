--[[
    The A0 arm's live program runs its scenarios with the bot harness's groups
    of the same names, counts and areas alike, its waits stay under 5 minutes,
    and a Studio run takes the timing of the program that holds its scenario
--]]

--!strict
local roblox: any = require("@lune/roblox") -- Its typedefs leave out the datatypes

local Harness = require("../../Fixtures/DevServer/Harness")
local Kit = require("../../Fixtures/Exploits/Kit")

local CONFIG: string = "dev/Arms/A0/Config.luau"
local TYPES: string = "dev/Arms/A0/Shared/Types.luau"
local PROGRAM: string = "dev/Arms/A0/Server/Program.luau"
local LIMIT: number = 300 -- Seconds from the first join the live program has, its calibrations and spawns on top
local SEED: number = 1
local UNKNOWN: string = "S99" -- A scenario no program runs

-- A program of the case's own, so each figure of its length can only have come from it
local OWN: { [string]: any } = {
	scenarios = { "A", "B" },
	seeds = { 1, 2 },
	warmupSeconds = 3,
	steadySeconds = 5,
	startDelay = 7,
	pauseSeconds = 11,
}

local OWN_LENGTH: number = 7 + 4 * (3 + 5) + 3 * 11 -- Its delay, 4 runs and the 3 pauses between them

-- The same program running the probe, which waits one more pause before it
local PROBED: { [string]: any } = table.clone(OWN)
PROBED.parallelProbe = true

local PROBED_LENGTH: number = OWN_LENGTH + 11

local function child(className: string, name: string, parent: any): any
	local made: any = roblox.Instance.new(className)
	made.Name = name
	made.Parent = parent

	return made
end

-- Whether two areas are both missing, or alike in center and size
local function same(ours: any, theirs: any): boolean
	if ours == nil or theirs == nil then
		return ours == theirs
	end

	return ours.center == theirs.center and ours.size == theirs.size
end

return function (): (boolean, string | nil)
	local loaded: Harness.Loaded = Harness.load()
	local dataModel: any = loaded.game
	local serverScripts: any = dataModel:GetService("ServerScriptService")
	local bench: { [string]: any } = loaded.require(serverScripts.Server.Bots.Config).scenarios

	-- A0's modules where arm-a0.project.json puts them, with stand-ins for the bots and the run
	local shared: any = child("Folder", "Arm", dataModel:GetService("ReplicatedStorage"))
	local arm: any = child("Folder", "Arm", serverScripts)
	local config: any = child("ModuleScript", "Config", shared)
	local types: any = child("ModuleScript", "Types", shared)
	local program: any = child("ModuleScript", "Program", arm)
	local bots: any = child("ModuleScript", "Bots", arm)
	local runner: any = child("ModuleScript", "Run", arm)

	-- Keeps the program each start hands the run
	local given: any = nil
	local run: { [string]: any } = {
		start = function (label: string, _: any, timing: any): (boolean, string)
			given = timing
			return true, label
		end,
	}

	local files: { [any]: string } = { [config] = CONFIG, [types] = TYPES, [program] = PROGRAM }
	local results: { [any]: any } = { [bots] = {}, [runner] = run }
	local load: (target: any) -> any = Kit.loader(dataModel, files, results, loaded.require)
	local Config: any = load(config)
	local Program: any = load(program)

	-- 1) Each scenario of the live program matches the harness's of the same name, group by group
	local live: any = Config.programs[Config.program]
	if not live then
		return false, `A0's live program {Config.program} is not among its programs`
	end

	for _, name: string in live.scenarios do
		local ours: any = Config.scenarios[name]
		local theirs: any = bench[name]
		if not ours or not theirs then
			return false, `{name}, which A0's live program runs, is missing from A0's scenarios or the bot harness's`
		elseif #ours.groups ~= #theirs.groups then
			return false, `A0's {name} has {#ours.groups} groups and the bot harness's {#theirs.groups}`
		end

		for index: number, group: any in ours.groups do
			local other: any = theirs.groups[index]
			if group.count ~= other.count or not same(group.spawn, other.spawn) or not same(group.roam, other.roam) then
				return false, `A0's {name} group {index} differs from the bot harness's in its count, spawn or roam`
			end
		end
	end

	-- 2) The live program's waits stay under the limit, and a length counts the pauses between runs and before a probe
	local length: number = Program.length(live)
	if length >= LIMIT then
		return false, `A0's live program waits {length} s, not under {LIMIT}`
	end

	local own: number = Program.length(OWN)
	if own ~= OWN_LENGTH then
		return false, `A program of 4 runs gave a length of {own} s, not {OWN_LENGTH}`
	end

	local probed: number = Program.length(PROBED)
	if probed ~= PROBED_LENGTH then
		return false, `The same program running the probe gave a length of {probed} s, not {PROBED_LENGTH}`
	end

	-- 3) A Studio start takes the live program's timing for a scenario it runs, else the timing of the program that does
	for _, holder: any in Config.programs do
		for _, scenario: string in holder.scenarios do
			given = nil

			local started: boolean = Program.start(scenario, SEED)
			local expected: any = table.find(live.scenarios, scenario) and live or holder
			if not started or given ~= expected then
				return false, `A Studio start of {scenario} took another program's timing`
			end
		end
	end

	-- 4) A scenario no program runs is refused before it reaches the run
	given = nil

	local started: boolean, refusal: string = Program.start(UNKNOWN, SEED)
	if started or given ~= nil then
		return false, `A start of {UNKNOWN} was taken: {refusal}`
	end

	return true, nil
end
