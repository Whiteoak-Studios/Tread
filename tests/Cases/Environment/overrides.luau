--[[
    An override answers the require of the ModuleScript at its dotted path,
    in place of a mounted file or where nothing is, and one naming a Folder
    is refused
--]]

--!strict
local Environment = require("../../Environment")

local GLOBALS: string = "tests/Fixtures/Environment/Globals.luau"
local REQUIRES_ABSENT: string = "tests/Fixtures/Environment/RequiresAbsent.luau"
local COUNTER: string = "ServerScriptService.Fixtures.Environment.Counter"
local ABSENT: string = "ServerScriptService.Fixtures.Environment.Absent" -- No file mounts here
local FOLDER: string = "ServerScriptService.Fixtures.Environment"

return function (): (boolean, string | nil)
	local fake: { [string]: any } = { count = -1 }
	local globals: any = Environment.load(GLOBALS, { [COUNTER] = fake })

	if globals.require(globals.script.Parent.Counter) ~= fake then
		return false, "The override for Counter did not answer its require in place of Counter.luau"
	end

	local absent: { [string]: any } = { absent = true }
	local found: any = Environment.load(REQUIRES_ABSENT, { [ABSENT] = absent })

	if found ~= absent then
		return false, `RequiresAbsent.luau handed back {found}, not the override made at {ABSENT}`
	end

	local loaded: boolean, message: any = pcall(Environment.load, GLOBALS, { [FOLDER] = absent })
	if loaded or string.find(`{message}`, FOLDER, 1, true) == nil then
		return false, `An override naming the Folder {FOLDER} was not refused by name: {message}`
	end

	return true, nil
end
