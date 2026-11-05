--[[
    A module that cannot load errors naming itself: one that throws, each
    time it is required, one that returns two values and one in a cycle
--]]

--!strict
local Environment = require("../../Environment")

local GLOBALS: string = "tests/Fixtures/Environment/Globals.luau"
local THROWS: string = "tests/Fixtures/Environment/Throws.luau"
local THROWN: string = "Throws.luau throws while loading" -- What Throws.luau's error says

-- Each fixture that cannot load, with the text its failure must hold beside the fixture's path
local FAILURES: { { path: string, says: string } } = {
	{ path = THROWS, says = THROWN },
	{ path = "tests/Fixtures/Environment/ReturnsTwo.luau", says = "returned 2 values" },
	{ path = "tests/Fixtures/Environment/Cycle.luau", says = "still loading" },
}

return function (): (boolean, string | nil)
	for _, failure: { path: string, says: string } in FAILURES do
		local loaded: boolean, message: any = pcall(Environment.load, failure.path)
		if loaded then
			return false, `{failure.path} loaded, though it cannot`
		end

		for _, part: string in { failure.path, failure.says } do
			if string.find(`{message}`, part, 1, true) == nil then
				return false, `{failure.path} failed without saying {part}: {message}`
			end
		end
	end

	-- A second require of a module that threw throws again, never read as one still loading
	local globals: any = Environment.load(GLOBALS)

	for attempt: number = 1, 2 do
		local required: boolean, message: any = pcall(globals.require, globals.script.Parent.Throws)
		if required or string.find(`{message}`, THROWN, 1, true) == nil then
			return false, `Require {attempt} of Throws.luau did not report its throw: {message}`
		end
	end

	return true, nil
end
