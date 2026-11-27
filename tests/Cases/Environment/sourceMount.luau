--[[
    src mounts as ReplicatedStorage.Packages.Tread beside Promise and Volt,
    as a Folder while it holds no init.luau, and the fixtures in their place
--]]

--!strict
local fs = require("@lune/fs")

local Environment = require("../../Environment")

local GLOBALS: string = "tests/Fixtures/Environment/Globals.luau"
local SIBLINGS: { string } = { "Promise", "Volt" } -- The packages a game installs beside Tread

return function (): (boolean, string | nil)
	local globals: any = Environment.load(GLOBALS)
	local packages: any = globals.game:GetService("ReplicatedStorage"):FindFirstChild("Packages")
	if not packages then
		return false, "ReplicatedStorage.Packages is missing"
	end

	for _, name: string in SIBLINGS do
		local module: any = packages:FindFirstChild(name)
		if not module or module.ClassName ~= "ModuleScript" then
			return false, `ReplicatedStorage.Packages.{name} is no ModuleScript beside Tread`
		end
	end

	-- Absent with no src, a Folder until src holds an init.luau and a ModuleScript after, as Rojo maps the folder
	local expected: string? = nil
	if fs.isFile("src/init.luau") then
		expected = "ModuleScript"
	elseif fs.isDir("src") then
		expected = "Folder"
	end

	local tread: any = packages:FindFirstChild("Tread")
	local mounted: string? = tread and tread.ClassName
	if mounted ~= expected then
		return false, `src mounted as {mounted}, where the files in it make it {expected}`
	end

	-- A Folder is no module, so requiring it fails, naming it
	if expected == "Folder" then
		local required: boolean, message: any = pcall(globals.require, tread)
		if required or string.find(`{message}`, "ReplicatedStorage.Packages.Tread", 1, true) == nil then
			return false, `Requiring src with no init.luau did not fail naming it: {message}`
		end
	end

	if globals.game:GetService("ServerScriptService"):FindFirstChild("Fixtures") == nil then
		return false, "tests/Fixtures is not mounted as ServerScriptService.Fixtures"
	end

	return true, nil
end
