--[[
    The dev game's shared table for a case, loaded as the dev place runs it:
    in a fresh fake game with Tread mounted and the place's test content
    folder in its Workspace, beside the Config and the fixture it checks by
--]]

--!strict
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox: any = require("@lune/roblox") -- Its typedefs leave out the datatypes and implementMethod

local Environment = require("../../Environment")

local GLOBALS: string = "tests/Fixtures/Environment/Globals.luau"
local SOURCE: string = "dev/Shared/Config.luau" -- Mounted as ReplicatedStorage.Shared.Dev.Config in the place
local CONTENT: string = "TestContent" -- The folder under Workspace the dev place holds its test content in
local DATATYPE: string = "^%u" -- A name Lune's library holds a Roblox datatype or Instance under

export type Loaded = {
	shared: any, -- What the dev module returns
	content: any, -- The fake game's test content folder
	terrain: any, -- Its Workspace's Terrain
	Config: any, -- Tread's Config, loaded in the same game
	Example: any, -- The approved example's fixture, loaded in the same game
}

-- Lune's Workspace has no WaitForChild, so the fake game's answers at once with what it holds. Registered once for
-- the whole run, since Lune refuses a method registered twice
roblox.implementMethod("Workspace", "WaitForChild", function (workspace: any, name: string, _: number?): any
	return workspace:FindFirstChild(name)
end)

local Harness = {}

--[[
    Runs the dev module in a fresh environment, under the same game,
    require and datatypes Tread's own modules get there, and hands back
    what it returned with the instances and modules a case checks it by
--]]

function Harness.load(): Loaded
	local globals: any = Environment.load(GLOBALS)
	local dataModel: any = globals.game
	local workspace: any = dataModel:GetService("Workspace")

	local content: any = roblox.Instance.new("Folder")
	content.Name = CONTENT
	content.Parent = workspace

	local scope: { [string]: any } = { game = dataModel, require = globals.require }
	for name: string, value: any in roblox do
		if name:match(DATATYPE) then
			scope[name] = value
		end
	end

	local chunk: () -> any = luau.load(fs.readFile(SOURCE), { debugName = SOURCE, environment = scope })
	local tread: any = dataModel:GetService("ReplicatedStorage").Packages.Tread
	local fixtures: any = dataModel:GetService("ServerScriptService").Fixtures

	return {
		shared = chunk(),
		content = content,
		terrain = workspace.Terrain,
		Config = globals.require(tread.Config),
		Example = globals.require(fixtures.Config.Example),
	}
end

return Harness
