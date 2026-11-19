--[[
    A file loads by its repo-relative path and hands back what it returns,
    and a path no mount holds, a real file outside them included, is refused
--]]

--!strict
local Environment = require("../../Environment")

local COUNTER: string = "tests/Fixtures/Environment/Counter.luau"
local UNMOUNTED: string = "tests/Cases/Environment/loadsByPath.luau" -- This case, a real file outside every mount
local MISSING: string = "src/Missing.luau"

return function (): (boolean, string | nil)
	local counter: any = Environment.load(COUNTER)
	if type(counter) ~= "table" or counter.count ~= 0 then
		return false, `{COUNTER} handed back {counter}, not its table`
	end

	for _, path: string in { UNMOUNTED, MISSING } do
		local loaded: boolean, message: any = pcall(Environment.load, path)
		if loaded then
			return false, `{path} loaded, though no mount holds it`
		end

		if string.find(`{message}`, path, 1, true) == nil then
			return false, `Loading {path} failed without naming it: {message}`
		end
	end

	return true, nil
end
