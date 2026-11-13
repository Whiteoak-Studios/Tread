--[[
    A fresh fake game for a case with the dev game's server side mounted as
    dev.project.json mounts it, dev/Server, dev/Shared and the dev scope's
    generated modules beside Tread, and a require that runs them in place
--]]

--!strict
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox: any = require("@lune/roblox") -- Its typedefs leave out the datatypes
local task = require("@lune/task")

local Environment = require("../../Environment")

local GLOBALS: string = "tests/Fixtures/Environment/Globals.luau"
local MODULE_FILE: string = "^(.+)%.luau$" -- A file's name without its extension
local SCRIPT_FILE: string = "%.%a+%.luau$" -- A bootstrap such as init.server.luau, which runs as a Script
local DATATYPE: string = "^%u" -- A name Lune's library holds a Roblox datatype or Instance under

-- Where dev.project.json mounts each folder of the dev game's server side: a service, then the path inside it
type Mount = { directory: string, service: string, path: { string } }

local MOUNTS: { Mount } = {
	{ directory = "dev/Server", service = "ServerScriptService", path = { "Server" } },
	{ directory = "dev/Network", service = "ReplicatedStorage", path = { "Shared", "Network" } },
	{ directory = "dev/Shared", service = "ReplicatedStorage", path = { "Shared", "Dev" } },
}

export type Loaded = {
	game: any, -- The fake game
	require: (target: any) -> any, -- Requires a dev module by its instance, or anything Tread's environment mounts
	mock: any, -- The Volt mock the dev scope's runtimes run over
}

type Module = { path: string, loaded: boolean, result: any }

local Harness = {}

-- The folder at a path inside a service, made with each folder on the way
local function folderAt(dataModel: any, service: string, path: { string }): any
	local current: any = dataModel:GetService(service)

	for _, name: string in path do
		local found: any = current:FindFirstChild(name)
		if not found then
			found = roblox.Instance.new("Folder")
			found.Name = name
			found.Parent = current
		end

		current = found
	end

	return current
end

-- A ModuleScript for each module file under a directory, its folders as Folders, each module's file kept by instance
local function mount(directory: string, parent: any, modules: { [any]: Module })
	for _, entry: string in fs.readDir(directory) do
		local path: string = `{directory}/{entry}`
		local stem: string? = entry:match(MODULE_FILE)

		if fs.isDir(path) then
			local folder: any = roblox.Instance.new("Folder")
			folder.Name = entry
			folder.Parent = parent
			mount(path, folder, modules)
		elseif stem and not entry:match(SCRIPT_FILE) then
			local module: any = roblox.Instance.new("ModuleScript")
			module.Name = stem
			module.Parent = parent
			modules[module] = { path = path, loaded = false, result = nil }
		end
	end
end

--[[
    Builds the fake game: Tread's environment, with the dev game's modules
    mounted where the place has them. Its require runs a dev module once,
    with script set to it and the Roblox datatypes in scope, and hands any
    other instance to Tread's environment
--]]

function Harness.load(): Loaded
	local globals: any = Environment.load(GLOBALS)
	local dataModel: any = globals.game
	local modules: { [any]: Module } = {}

	for _, entry: Mount in MOUNTS do
		mount(entry.directory, folderAt(dataModel, entry.service, entry.path), modules)
	end

	local function load(target: any): any
		local module: Module? = modules[target]
		if not module then
			return globals.require(target)
		elseif module.loaded then
			return module.result
		end

		local scope: { [string]: any } = { game = dataModel, script = target, require = load, task = task }
		for name: string, value: any in roblox do
			if name:match(DATATYPE) then
				scope[name] = value
			end
		end

		local chunk: () -> any = luau.load(fs.readFile(module.path), { debugName = module.path, environment = scope })
		module.result = chunk()
		module.loaded = true

		return module.result
	end

	local packages: any = dataModel:GetService("ReplicatedStorage").Packages

	return {
		game = dataModel,
		require = load,
		mock = globals.require(packages.Volt).mock,
	}
end

return Harness
