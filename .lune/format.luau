--[[
    Formats every .luau file under src, tests and dev with StyLua, skipping
    what .styluaignore lists, then puts back the space after an anonymous
    function's keyword, which StyLua removes. A missing folder is skipped
--]]

--!strict
local fs = require("@lune/fs")
local process = require("@lune/process")

local ROOTS: { string } = { "src", "tests", "dev" }
local IGNORE_FILE: string = ".styluaignore" -- Volt's output, which the editor's StyLua skips too
local FOLDER_GLOB: string = "/%*%*$" -- A line ending in /** skips the folder it names
local BATCH_CAP: number = 16000 -- Characters of paths a StyLua run takes; a Windows command line holds 32,767

local Skipped: { [string]: boolean } = {}
local Files: { string } = {}

-- Whiteoak TODO: a .styluaignore line is an exact path or a folder/**; match full globs here once a line needs one
for line: string in fs.readFile(IGNORE_FILE):gmatch("[^\r\n]+") do
	local path: string = (line:gsub(FOLDER_GLOB, ""))

	if path:find("*", 1, true) then
		error(`{IGNORE_FILE} line {line} is a glob this script cannot match; list a path or a folder/**`)
	end

	Skipped[path] = true
end

--[[
    Collects every .luau file under a directory, skipping the paths and
    folders .styluaignore lists
--]]

local function collect(directory: string)
	for _, name: string in fs.readDir(directory) do
		local path: string = `{directory}/{name}`

		if Skipped[path] then
			continue
		end

		if fs.isDir(path) then
			collect(path)
		elseif name:match("%.luau$") then
			table.insert(Files, path)
		end
	end
end

for _, root: string in ROOTS do
	if fs.isDir(root) then
		collect(root)
	end
end

-- StyLua exits 2 when it is given no paths
if #Files == 0 then
	return print(`No .luau files to format under {table.concat(ROOTS, ", ")}`)
end

--[[
    Runs StyLua over one batch of paths, stopping the script with StyLua's
    exit code when the batch fails
--]]

local function format(batch: { string })
	local result: process.ExecResult = process.exec("stylua", batch, { stdio = "forward" })

	if not result.ok then
		print(`StyLua failed on a batch of {#batch} files starting at {batch[1]}`)
		process.exit(result.code)
	end
end

local Batch: { string } = {}
local length: number = 0

-- Each path counts the space before it, so no run's command line passes the cap
for _, path: string in Files do
	if #Batch > 0 and length + #path + 1 > BATCH_CAP then
		format(Batch)
		table.clear(Batch)
		length = 0
	end

	table.insert(Batch, path)
	length += #path + 1
end

format(Batch)

-- Only an anonymous function puts a parenthesis straight after the keyword, so the restore is safe
for _, path: string in Files do
	local source: string = fs.readFile(path)
	local restored: string = source:gsub("%f[%w_]function%(", "function (")

	if restored ~= source then
		fs.writeFile(path, restored)
	end
end
