--[[
    Fixtures mount as Rojo maps them, so script.Parent reaches a sibling,
    an init.luau sits at its folder's level and each folder down adds one
--]]

--!strict
local Environment = require("../../Environment")

local GLOBALS: string = "tests/Fixtures/Environment/Globals.luau"
local FOLDER: string = "ServerScriptService.Fixtures.Environment" -- Where tests/Fixtures/Environment mounts

return function (): (boolean, string | nil)
	local globals: any = Environment.load(GLOBALS)
	local folder: any = globals.script.Parent

	if folder:GetFullName() ~= FOLDER or folder.ClassName ~= "Folder" then
		return false, `tests/Fixtures/Environment mounted as the {folder.ClassName} {folder:GetFullName()}`
	end

	-- A sibling resolves through script.Parent, and a second require in one environment hands back the same table
	local counter: any = globals.require(folder.Counter)
	if type(counter) ~= "table" or counter.count ~= 0 then
		return false, `script.Parent.Counter handed back {counter}, not Counter's table`
	end

	if globals.require(folder.Counter) ~= counter then
		return false, "A second require of Counter in the same environment ran it again"
	end

	-- A folder holding an init.luau is a ModuleScript, and its other files are its children
	local nested: any = folder.Nested
	if nested.ClassName ~= "ModuleScript" or nested:FindFirstChild("Inner") == nil then
		return false, `Nested mounted as a {nested.ClassName} without Inner beneath it`
	end

	if globals.require(nested) ~= counter then
		return false, "Nested/init.luau's script.Parent.Counter is not the Counter beside its folder"
	end

	if globals.require(nested.Inner) ~= counter then
		return false, "Nested/Inner.luau's script.Parent.Parent.Counter is not the Counter beside its folder"
	end

	return true, nil
end
