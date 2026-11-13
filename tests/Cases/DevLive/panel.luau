--[[
    The live panel shows a run as the server reports it: running clears
    the report, pieces add to it, a verdict and a refusal set the status
    alone, and the panel's key is free of every other key the dev client binds
--]]

--!strict
local fs = require("@lune/fs")

local Harness = require("../../Fixtures/DevClient/Harness")

local LIVE_RUNS: string = "dev/Shared/LiveRuns.luau"
local CONFIG: string = "dev/Client/Config.luau"
local INPUT: string = "dev/Client/Input.luau"
local CLIENT: string = "dev/Client" -- Every file the dev client runs, the kit's tools among them
local MODULE_FILE: string = "%.luau$"
local KEY_CODE: string = "Enum%.KeyCode%.(%w+)" -- A key written into the dev client, by its name

-- One report from the server, and what the panel then shows
type Step = { state: string, text: string, status: string, report: string }

-- Every Enum.KeyCode name written into the dev client's files under a folder, each once a place it is written
local function keyNames(directory: string, into: { string })
	for _, entry: string in fs.readDir(directory) do
		local path: string = `{directory}/{entry}`
		if fs.isDir(path) then
			keyNames(path, into)
		elseif entry:match(MODULE_FILE) then
			for name: string in fs.readFile(path):gmatch(KEY_CODE) do
				table.insert(into, name)
			end
		end
	end
end

return function (): (boolean, string | nil)
	local place: Harness.Game = Harness.new()
	local LiveRuns: any = place.load(LIVE_RUNS)
	local first: any = LiveRuns.runs[1]
	local second: any = LiveRuns.runs[2]

	local steps: { Step } = {
		{
			state = "Running",
			text = first.name,
			status = `Running {first.name}, about {first.minutes} min`,
			report = "",
		},
		{ state = "Piece", text = "one ", status = `Running {first.name}, about {first.minutes} min`, report = "one " },
		{
			state = "Piece",
			text = "two",
			status = `Running {first.name}, about {first.minutes} min`,
			report = "one two",
		},
		{ state = "Passed", text = first.name, status = `Done: {first.name} passed`, report = "one two" },

		-- A refused click keeps the report not yet copied
		{
			state = "Refused",
			text = `no live run is named NoSuchRun`,
			status = `Refused: no live run is named NoSuchRun`,
			report = "one two",
		},

		-- The next run clears it
		{
			state = "Running",
			text = second.name,
			status = `Running {second.name}, about {second.minutes} min`,
			report = "",
		},
		{
			state = "Piece",
			text = "three",
			status = `Running {second.name}, about {second.minutes} min`,
			report = "three",
		},
		{ state = "Failed", text = second.name, status = `Failed: {second.name}`, report = "three" },
	}

	-- 1) The reducer's sequence, from the idle panel
	local panel: any = LiveRuns.idle()
	if panel.status ~= "Idle" or panel.text ~= "" then
		return false, `The idle panel shows {panel.status} over {panel.text}`
	end

	for index: number, step: Step in steps do
		local before: any = panel
		panel = LiveRuns.apply(panel, step.state, step.text)

		if panel.status ~= step.status or panel.text ~= step.report then
			return false, `After step {index}, {step.state}, the panel shows {panel.status} over {panel.text}`
		elseif before == panel then
			return false, `Step {index}, {step.state}, changed the panel it was given in place`
		end
	end

	-- 2) The panel's key is written into the dev client once, in its own block, and drives none of the dev input
	local key: EnumItem = place.load(CONFIG).live.key
	local names: { string } = {}
	keyNames(CLIENT, names)

	local written: number = 0
	for _, name: string in names do
		if name == key.Name then
			written += 1
		end
	end

	if written ~= 1 then
		return false, `The panel's key {key.Name} is written {written} times into the dev client, not once`
	end

	local Input: any = place.load(INPUT)
	local Command: any = place.tread("Codec.Command")
	local pressed: any = Input.new()
	local rest: any = Input.new()
	pressed:press(key.Name, true)

	local held: any = Command.new()
	local idle: any = Command.new()
	pressed:sample(held)
	rest:sample(idle)

	for field: string, value: any in held do
		if type(value) ~= "table" and value ~= idle[field] then
			return false, `The panel's key {key.Name} drives the dev input's {field}`
		end
	end

	return true, nil
end
