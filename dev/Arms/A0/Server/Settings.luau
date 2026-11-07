--[[
    Reads each Workspace setting the arm's project file sets, at the server's
    start, and records which kept that value, which changed and which no
    script can read
--]]

--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Arm.Config)
local Run = require(ServerScriptService.Arm.Run)

local ARM: string = Config.arm
local SEPARATOR: string = ", " -- Between the settings of one list
local SECTIONS: string = "; " -- Between the lists of the report line

local Types = require(ReplicatedStorage.Arm.Types)

type Setting = Types.Setting

local Settings = {}

--[[
    A Workspace property by name. Reading one that no script may read
    errors, which the caller's pcall turns into an unreadable setting
--]]

local function read(property: string): any
	return (Workspace :: any)[property]
end

--[[
    The names in a list, or none
--]]

local function list(names: { string }): string
	return #names > 0 and table.concat(names, SEPARATOR) or "none"
end

--[[
    Compares every configured setting with the value read back now, records
    the comparison as one report line and returns it
--]]

function Settings.record(): string
	local kept: { string } = {}
	local changed: { string } = {}
	local unreadable: { string } = {}

	for _, setting: Setting in Config.settings do
		local readable: boolean, value: any = pcall(read, setting.property)
		if not readable then
			table.insert(unreadable, setting.property)
		elseif value == setting.set then
			table.insert(kept, `{setting.property} {setting.set}`)
		else
			table.insert(changed, `{setting.property} from {setting.set} to {value}`)
		end
	end

	local parts: { string } = {
		`{ARM} settings: changed from the project file: {list(changed)}`,
		`kept: {list(kept)}`,
		`no script can read: {list(unreadable)}`,
	}

	local line: string = table.concat(parts, SECTIONS)
	Run.record(line)

	return line
end

return Settings
