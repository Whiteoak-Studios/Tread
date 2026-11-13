--[[
    Loads the dev game's client modules for a case as the dev place runs
    them, each in one fresh fake game with Tread mounted, whose require also
    hands the case Tread's own modules and the fixtures
--]]

--!strict
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox: any = require("@lune/roblox") -- Its typedefs leave out the datatypes

local Environment = require("../../Environment")

local GLOBALS: string = "tests/Fixtures/Environment/Globals.luau"
local DATATYPE: string = "^%u" -- A name Lune's library holds a Roblox datatype, Enum or Instance under

export type Game = {
	game: any, -- The fake game
	load: (path: string) -> any, -- What a dev module at a repo-relative path returns, run in this game
	tread: (path: string) -> any, -- A module of Tread's, by its dotted path inside the package
	fixture: (path: string) -> any, -- A fixture, by its dotted path inside tests/Fixtures
}

local Harness = {}

--[[
    A fresh fake game, under the same game, require and datatypes Tread's
    own modules get there, which loads dev modules and hands out Tread's
    modules and the fixtures by their place in it
--]]

function Harness.new(): Game
	local globals: any = Environment.load(GLOBALS)
	local dataModel: any = globals.game

	local scope: { [string]: any } = { game = dataModel, require = globals.require }
	for name: string, value: any in roblox do
		if name:match(DATATYPE) then
			scope[name] = value
		end
	end

	-- The instance at a dotted path below a folder, as the game's require takes it
	local function find(root: any, path: string): any
		local instance: any = root
		for _, segment: string in path:split(".") do
			instance = instance:FindFirstChild(segment)
		end

		return instance
	end

	return {
		game = dataModel,

		load = function (path: string): any
			local chunk: () -> any = luau.load(fs.readFile(path), { debugName = path, environment = scope })

			return chunk()
		end,

		tread = function (path: string): any
			local package: any = dataModel:GetService("ReplicatedStorage").Packages.Tread

			return globals.require(find(package, path))
		end,

		fixture = function (path: string): any
			return globals.require(find(dataModel:GetService("ServerScriptService").Fixtures, path))
		end,
	}
end

return Harness
