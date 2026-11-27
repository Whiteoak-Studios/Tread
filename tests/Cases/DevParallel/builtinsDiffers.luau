--[[
    What the B2 battery's differences names, one line each: a section's hash,
    a failure on either side, a shape, a missing section, the order and the
    timing loop's end, and nothing for an equal copy or one timed otherwise
--]]

--!strict
local roblox: any = require("@lune/roblox") -- Its typedefs leave out the datatypes

local Harness = require("../../Fixtures/DevServer/Harness")

local CHANGED: number = 7 -- The section each copy changes, one in the middle of the battery
local WORD: number = 4294967296 -- 2^32, which a changed hash wraps at
local HASH: string = "%08x" -- How a line writes a hash
local FAILURE: string = "a planted failure"
local SEPARATOR: string = " | "

-- A copy whose fields and sections can change without touching the original
local function copy(result: any): any
	local copied: any = table.clone(result)
	copied.sections = {}

	for index: number, entry: any in result.sections do
		copied.sections[index] = table.clone(entry)
	end

	return copied
end

-- Why those lines are not one line holding every needle, or nil when they are
local function single(lines: { string }, needles: { string }): string?
	if #lines ~= 1 then
		return `gave {#lines} lines: {table.concat(lines, SEPARATOR)}`
	end

	for _, needle: string in needles do
		if string.find(lines[1], needle, 1, true) == nil then
			return `gave "{lines[1]}", which does not name "{needle}"`
		end
	end

	return nil
end

return function (): (boolean, string | nil)
	local loaded: any = Harness.load()
	local Builtins: any = loaded.require(loaded.game:GetService("ServerScriptService").Server.Parallel.Builtins)
	local result: any = Builtins.run(roblox.Instance.new("Part"))
	local name: string = result.sections[CHANGED].name

	-- 1) An equal copy, the result itself and a copy whose loop took another time give nothing
	local timed: any = copy(result)
	timed.loopMs += 1

	local alike: { [string]: any } = { ["an equal copy"] = copy(result), ["itself"] = result, ["another time"] = timed }
	for label: string, other: any in alike do
		local lines: { string } = Builtins.differences(result, other)
		if #lines > 0 then
			return false, `Against {label} it gave {table.concat(lines, SEPARATOR)}`
		end
	end

	-- 2) A changed hash, named with both hashes
	local hashed: any = copy(result)
	local old: number = result.sections[CHANGED].hash
	hashed.sections[CHANGED].hash = (old + 1) % WORD

	local problem: string? = single(Builtins.differences(result, hashed), {
		name,
		string.format(HASH, old),
		string.format(HASH, hashed.sections[CHANGED].hash),
	})
	if problem then
		return false, `A changed hash {problem}`
	end

	-- 3) A failure with its hash unchanged, on their side and on ours
	local failed: any = copy(result)
	failed.sections[CHANGED].failure = FAILURE

	problem = single(Builtins.differences(result, failed), { name, FAILURE })
	if problem then
		return false, `Their failure {problem}`
	end

	problem = single(Builtins.differences(failed, result), { name, FAILURE })
	if problem then
		return false, `Our failure {problem}`
	end

	-- 4) A section with another record count
	local shaped: any = copy(result)
	shaped.sections[CHANGED].records += 1

	problem = single(Builtins.differences(result, shaped), { name })
	if problem then
		return false, `A changed shape {problem}`
	end

	-- 5) A section missing from either side
	local missing: any = copy(result)
	table.remove(missing.sections, CHANGED)

	problem = single(Builtins.differences(result, missing), { name, "missing from theirs" })
	if problem then
		return false, `A section they lack {problem}`
	end

	problem = single(Builtins.differences(missing, result), { name, "missing from ours" })
	if problem then
		return false, `A section we lack {problem}`
	end

	-- 6) Every section alike but the whole stream hashing apart, which only another order gives
	local reordered: any = copy(result)
	local moved: any = table.remove(reordered.sections, CHANGED)
	table.insert(reordered.sections, CHANGED + 1, moved)
	reordered.hash = (result.hash + 1) % WORD

	problem = single(Builtins.differences(result, reordered), { "order" })
	if problem then
		return false, `Another order {problem}`
	end

	-- 7) The timing loop ending elsewhere
	local looped: any = copy(result)
	looped.loopValue += 1

	problem = single(Builtins.differences(result, looped), { "timing loop" })
	if problem then
		return false, `Another loop end {problem}`
	end

	return true, nil
end
