--[[
    The B2 battery's 36 sections in the parity spike's order, names, widths
    and record counts, each run under Lune with no failure, in a result of
    plain strings, numbers and tables that can cross between VMs
--]]

--!strict
local roblox: any = require("@lune/roblox") -- Its typedefs leave out the datatypes

local Harness = require("../../Fixtures/DevServer/Harness")

local LERP: number = 4096 -- The battery's input counts, as the parity spike sets them
local SMALL: number = 512
local EXACT: number = 256
local CFRAMES: number = 256
local WORD: number = 4294967296 -- 2^32, above every hash

-- Each section's name, values a record and records, in the battery's order
local EXPECTED: { { name: string, width: number, records: number } } = {
	{ name = "math.lerp", width = 1, records = LERP },
	{ name = "a + (b - a) * t", width = 1, records = LERP },
	{ name = "a % b", width = 1, records = LERP },
	{ name = "vector.lerp", width = 3, records = LERP },
	{ name = "u + (v - u) * t", width = 3, records = LERP },
	{ name = "vector.magnitude", width = 1, records = SMALL },
	{ name = "vector.normalize", width = 3, records = SMALL },
	{ name = "vector.dot", width = 1, records = SMALL },
	{ name = "vector.cross", width = 3, records = SMALL },
	{ name = "vector.angle", width = 1, records = SMALL },
	{ name = "vector.floor, ceil, abs, sign", width = 12, records = EXACT },
	{ name = "vector.clamp, max, min", width = 9, records = EXACT },
	{ name = "vector operators", width = 18, records = SMALL },
	{ name = "Vector3:Lerp", width = 3, records = LERP },
	{ name = "U + (V - U) * t", width = 3, records = LERP },
	{ name = "Vector3.Magnitude", width = 1, records = SMALL },
	{ name = "Vector3.Unit", width = 3, records = SMALL },
	{ name = "Vector3:Dot", width = 1, records = SMALL },
	{ name = "Vector3:Cross", width = 3, records = SMALL },
	{ name = "Vector3:Angle", width = 1, records = SMALL },
	{ name = "Vector3:Floor, Ceil, Abs, Sign", width = 12, records = EXACT },
	{ name = "Vector3:Max, Min", width = 6, records = EXACT },
	{ name = "Vector3 operators", width = 18, records = SMALL },
	{ name = "CFrame.new with a quaternion", width = 12, records = CFRAMES },
	{ name = "CFrame.Angles", width = 12, records = CFRAMES },
	{ name = "CFrame.fromOrientation", width = 12, records = CFRAMES },
	{ name = "CFrame.fromAxisAngle", width = 12, records = CFRAMES },
	{ name = "CFrame.lookAt", width = 12, records = CFRAMES },
	{ name = "CFrame.lookAlong", width = 12, records = CFRAMES },
	{ name = "CFrame.fromMatrix", width = 12, records = CFRAMES },
	{ name = "CFrame * Vector3", width = 3, records = CFRAMES },
	{ name = "CFrame * CFrame", width = 12, records = CFRAMES },
	{ name = "CFrame:Inverse", width = 12, records = CFRAMES },
	{ name = "CFrame:Orthonormalize", width = 12, records = CFRAMES },
	{ name = "Part.CFrame written", width = 12, records = CFRAMES },
	{ name = "Part.CFrame written skewed", width = 12, records = CFRAMES },
}

-- The first thing in a value that is not a plain string, number or table without a metatable, or nil when it is all plain
local function unplain(value: unknown, path: string): string?
	if type(value) == "string" or type(value) == "number" then
		return nil
	elseif type(value) ~= "table" then
		return `{path} is a {typeof(value)}`
	elseif getmetatable(value :: any) ~= nil then
		return `{path} has a metatable`
	end

	for key: unknown, entry: unknown in value :: { [unknown]: unknown } do
		local found: string? = unplain(entry, `{path}.{tostring(key)}`)
		if found then
			return found
		end
	end

	return nil
end

-- Whether a number is a whole 32-bit word, as every hash must be
local function isWord(value: number): boolean
	return value >= 0 and value < WORD and value == math.floor(value)
end

return function (): (boolean, string | nil)
	local loaded: any = Harness.load()
	local Builtins: any = loaded.require(loaded.game:GetService("ServerScriptService").Server.Parallel.Builtins)
	local result: any = Builtins.run(roblox.Instance.new("Part"))

	-- 1) The sections in the spike's order, each with its name, width and records, none failing under Lune
	if #result.sections ~= #EXPECTED then
		return false, `The battery gave {#result.sections} sections, not {#EXPECTED}`
	end

	local values: number = 0
	for index: number, expected in EXPECTED do
		local entry: any = result.sections[index]
		if entry.name ~= expected.name or entry.width ~= expected.width or entry.records ~= expected.records then
			local shape: string = `"{entry.name}" with {entry.records} records of {entry.width}`
			local wanted: string = `"{expected.name}" with {expected.records} of {expected.width}`
			return false, `Section {index} is {shape}, not {wanted}`
		elseif entry.failure ~= nil then
			return false, `Section {index}, {entry.name}, failed under Lune: {entry.failure}`
		elseif not isWord(entry.hash) then
			return false, `Section {index}, {entry.name}, has the hash {entry.hash}, not a whole 32-bit word`
		end

		values += expected.width * expected.records
	end

	-- 2) Every value the sections hold is in the stream, and the whole stream's hash is a word too
	if result.values ~= values then
		return false, `The battery wrote {result.values} values where its sections hold {values}`
	elseif not isWord(result.hash) then
		return false, `The whole stream's hash is {result.hash}, not a whole 32-bit word`
	end

	-- 3) Plain data only, so it crosses a BindableEvent whole
	local found: string? = unplain(result, "result")
	if found then
		return false, `The result is not plain data: {found}`
	end

	return true, nil
end
