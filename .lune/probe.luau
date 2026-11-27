--[[
    Runs the scaffold probe's step fixture under Lune and prints its numbers
    as hex, or compares them line by line with a file another realm wrote
--]]

--!strict
local fs = require("@lune/fs")
local process = require("@lune/process")

local Probe = require("../tests/Fixtures/Probe")

local FLIP: string = "--flip"
local HEX_DIGITS: number = 16
local HEX_LINE: string = "^[0-9a-f]+$"
local FAILED: number = 1 -- The exit code a mismatch or a bad file gives

local function fail(message: string)
	print(message)
	process.exit(FAILED)
end

local flip: boolean = false
local path: string? = nil

for _, argument: string in process.args do
	if argument == FLIP then
		flip = true
	elseif path == nil and argument:sub(1, 2) ~= "--" then
		path = argument
	else
		return fail(`Unexpected argument {argument}; pass {FLIP}, a file to compare with, or both`)
	end
end

local ours: string = Probe.encode(Probe.run(flip))

if not path then
	return print(ours)
end

if not fs.isFile(path) then
	return fail(`{path} is not a file`)
end

local theirs: { string } = {}

-- Blank lines and Windows line endings are skipped, so a file saved on either side reads the same
for line: string in fs.readFile(path):gmatch("[^\r\n]+") do
	if #line ~= HEX_DIGITS or not line:match(HEX_LINE) then
		return fail(`Line {#theirs + 1} of {path} is not {HEX_DIGITS} lowercase hex digits: {line}`)
	end

	table.insert(theirs, line)
end

local lines: { string } = ours:split("\n")

if #theirs ~= #lines then
	return fail(`{path} holds {#theirs} lines and this run {#lines}`)
end

local first: number? = nil
local differing: number = 0

for index: number, line: string in lines do
	if theirs[index] ~= line then
		differing += 1
		first = first or index
	end
end

if first then
	local mismatch: string = `Line {first} differs: {path} has {theirs[first]}, this run {lines[first]}`

	return fail(`{mismatch}; {differing} of {#lines} lines differ`)
end

print(`All {#lines} lines match {path}`)
