--[[
    A require the environment cannot answer errors naming what it was
    given: a child the folder lacks, a Folder, a ModuleScript no mount made
    and a string path
--]]

--!strict
local roblox: any = require("@lune/roblox")

local Environment = require("../../Environment")

local GLOBALS: string = "tests/Fixtures/Environment/Globals.luau"
local REQUIRES_ABSENT: string = "tests/Fixtures/Environment/RequiresAbsent.luau"
local STRAY: string = "Stray" -- A ModuleScript the case makes, which no mount knows
local PATH: string = "./Counter" -- A string require, which Tread's code never makes

return function (): (boolean, string | nil)
	-- The module that requires a missing child fails, naming itself and the child
	local loaded: boolean, message: any = pcall(Environment.load, REQUIRES_ABSENT)
	if loaded then
		return false, `{REQUIRES_ABSENT} loaded, though no Absent is beside it`
	end

	for _, part: string in { REQUIRES_ABSENT, "Absent" } do
		if string.find(`{message}`, part, 1, true) == nil then
			return false, `Requiring a missing child failed without naming {part}: {message}`
		end
	end

	local globals: any = Environment.load(GLOBALS)
	local stray: any = roblox.Instance.new("ModuleScript")
	stray.Name = STRAY

	-- Each target with the text its refusal must name
	local targets: { { target: any, named: string } } = {
		{ target = globals.script.Parent, named = "Folder ServerScriptService.Fixtures.Environment" },
		{ target = stray, named = `ModuleScript {STRAY}` },
		{ target = PATH, named = PATH },
	}

	for _, case: { target: any, named: string } in targets do
		local required: boolean, refusal: any = pcall(globals.require, case.target)
		if required then
			return false, `require took {case.named}, which nothing mounted answers`
		end

		if string.find(`{refusal}`, case.named, 1, true) == nil then
			return false, `require refused {case.named} without naming it: {refusal}`
		end
	end

	return true, nil
end
