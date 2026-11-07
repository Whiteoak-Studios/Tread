--[[
    The entry `lune run tests` starts: runs every case under tests/Cases in
    path order, each on a thread of its own, and stops at the first failure
--]]

--!strict
local fs = require("@lune/fs")
local process = require("@lune/process")
local task = require("@lune/task")

local CASES: string = "tests/Cases"
local CASE_FILE: string = "%.luau$"
local CASE_LIMIT: number = 30 -- Real seconds a case may take before it fails as unfinished
local FAILED: number = 1 -- The exit code the first failing case ends the run with
local PASSED: number = 0

local Paths: { string } = {}

--[[
    Collects every case file under a directory, its folders included
--]]

local function collect(directory: string)
	for _, name: string in fs.readDir(directory) do
		local path: string = `{directory}/{name}`

		if fs.isDir(path) then
			collect(path)
		elseif name:match(CASE_FILE) then
			table.insert(Paths, path)
		end
	end
end

--[[
    Runs one case to the case contract: it fails when its require errors,
    when it returns no function, when it throws or never finishes, or when
    its first return is anything but true
--]]

local function run(path: string): (boolean, string | nil)
	-- In an init.luau, ./ is the folder's parent, the repo root the runner runs from
	local module: string = (path:gsub(CASE_FILE, ""))
	local loaded: boolean, case: any = pcall(require :: any, `./{module}`)
	if not loaded then
		return false, `its require failed: {case}`
	end

	if type(case) ~= "function" then
		return false, `it returned a {type(case)}, not a function`
	end

	-- A case runs on a thread of its own, so the deadline below ends one that never finishes
	local finished: boolean = false
	local ran: boolean, passed: any, reason: any = false, nil, nil
	task.spawn(function ()
		ran, passed, reason = pcall(case)
		finished = true
	end)

	local deadline: number = os.clock() + CASE_LIMIT
	while not finished and os.clock() < deadline do
		task.wait()
	end

	if not finished then
		return false, `it had not finished after {CASE_LIMIT} s`
	end

	if not ran then
		return false, `it threw: {passed}`
	end

	if passed ~= true then
		if reason == nil then
			return false, `it returned {passed} with no reason`
		end

		return false, `{reason}`
	end

	return true, nil
end

collect(CASES)
table.sort(Paths)

for _, path: string in Paths do
	local passed: boolean, reason: string? = run(path)

	if not passed then
		print(`Failed {path}: {reason}`)
		process.exit(FAILED)
	end
end

print(`{#Paths} cases passed`)

-- Ends the run even while a Heartbeat a case left connected keeps a thread waiting
process.exit(PASSED)
