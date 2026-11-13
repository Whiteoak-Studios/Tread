--[[
    Loads one src/ or tests/Fixtures/ file for a case in a fresh fake game,
    mounted where dev.project.json puts it, beside Promise and a Volt that
    starts every runtime over the environment's own mock
--]]

--!strict
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox: any = require("@lune/roblox") -- Its typedefs leave out the datatypes and implementProperty
local task = require("@lune/task")

local Volt = require("@volt")

local SOURCE: string = "src" -- Mounted as ReplicatedStorage.Packages.Tread, where a game's install puts it
local PACKAGE: string = "Tread"
local FIXTURES: string = "tests/Fixtures" -- Mounted as ServerScriptService.Fixtures, as dev.project.json maps it
local FIXTURES_NAME: string = "Fixtures"
local INIT: string = "init.luau"
local MODULE_FILE: string = "^(.+)%.luau$" -- A file's name without its extension
local PROMISE_LINK: string = "Packages/Promise.lua"
local PROMISE_FILE: string = "lib/init.lua" -- Promise's module inside the folder Wally installs it in
local LINK: string = `_Index%["([^"]+)"%]%["([^"]+)"%]` -- The folder a Wally link file points its alias at
local SERVER: string = "server" -- A server schema's side
local PLAYER: string = "Player" -- The Name of the player a client runtime joins the mock as
local FRAME: number = 1 / 60 -- Seconds between the fake Heartbeat's frames
local HEARTBEAT_LIMIT: number = 30 -- Real seconds one Heartbeat keeps firing, past the longest a case may run

type Module = {
	path: string, -- The file it runs, or what answers it in place of one
	loading: boolean,
	loaded: boolean,
	result: any,
}

type State = {
	modules: { [any]: Module }, -- Each ModuleScript this environment's require takes, by the instance
	paths: { [string]: any }, -- Each mounted file's ModuleScript, by its repo-relative path
	globals: { [string]: any },
}

type Connection = { Disconnect: (self: Connection) -> () }

type Heartbeat = {
	Connect: (self: Heartbeat, callback: (delta: number) -> ()) -> Connection,
	Wait: (self: Heartbeat) -> number,
}

-- The overlap queries made of every environment's Workspace, and the latest one's part and params
type PartsInPart = {
	calls: number,
	part: any,
	params: any,
}

-- Each file's text, read once a run, since no file changes while the suite runs
local Sources: { [string]: string } = {}

-- Each environment's Heartbeat by its RunService, held for the run so the getter is handed the instance stored
-- Whiteoak TODO: this holds every environment's RunService until the run ends; key it by an attribute id on the
-- RunService, so a finished environment can be collected, once a run's memory shows the cost
local Heartbeats: { [any]: Heartbeat } = {}

-- Lune has no overlap query, so OverlapParams is a plain table of the filter the stand-in below is handed
local OverlapParams: { new: () -> { [string]: any } } = {
	new = function (): { [string]: any }
		return {}
	end,
}

local PartsInPart: PartsInPart = { calls = 0, part = nil, params = nil }

local Environment = {}

-- What a case reads to learn that code asked the engine's overlap query, and with what
Environment.partsInPart = PartsInPart

assert(fs.isFile(PROMISE_LINK), `{PROMISE_LINK} is missing; run wally install`)

local installed: string?, alias: string? = fs.readFile(PROMISE_LINK):match(LINK)
assert(installed and alias, `{PROMISE_LINK} names no installed folder; run wally install`)

local promiseSource: string = `Packages/_Index/{installed}/{alias}/{PROMISE_FILE}`

-- Lune's RunService has no signals, so each environment's answers Heartbeat with a fake of its own
roblox.implementProperty("RunService", "Heartbeat", function (runService: any): Heartbeat
	return Heartbeats[runService]
end)

-- Lune's Workspace has no GetPartsInPart, so each environment's finds no part, keeping the call for a case to read
roblox.implementMethod("Workspace", "GetPartsInPart", function (_: any, part: any, params: any): { any }
	PartsInPart.calls += 1
	PartsInPart.part = part
	PartsInPart.params = params

	return {}
end)

--[[
    A Heartbeat on Lune's scheduler for Promise's timers: one thread fires
    every connection on a thread of its own once a frame, until the last
    one disconnects or the limit passes with one still connected
--]]

local function heartbeat(): Heartbeat
	local callbacks: { [{ nil }]: (delta: number) -> () } = {}
	local running: boolean = false

	local function pump()
		local deadline: number = os.clock() + HEARTBEAT_LIMIT

		while next(callbacks) ~= nil and os.clock() < deadline do
			local delta: number = task.wait(FRAME)

			-- A copy, so a callback that disconnects another mid-frame skips none and runs no disconnected one
			for token: { nil }, callback: (delta: number) -> () in table.clone(callbacks) do
				if callbacks[token] then
					task.spawn(callback, delta)
				end
			end
		end

		running = false

		if next(callbacks) ~= nil then
			warn(`The fake Heartbeat stopped after {HEARTBEAT_LIMIT} s with a connection still made`)
		end
	end

	return {
		Connect = function (_: Heartbeat, callback: (delta: number) -> ()): Connection
			local token: { nil } = {}
			callbacks[token] = callback

			if not running then
				running = true
				task.spawn(pump)
			end

			return {
				Disconnect = function (_: Connection)
					callbacks[token] = nil
				end,
			}
		end,

		Wait = function (_: Heartbeat): number
			return task.wait(FRAME)
		end,
	}
end

--[[
    What a generated module's require of ReplicatedStorage.Packages.Volt
    gets: start runs its runtime over the environment's mock, as the server
    or as a player it joins, and mock is that mock, for a case to drive
--]]

local function voltStandIn(): { [string]: any }
	local mock: Volt.Mock = Volt.mock(task.spawn)

	return {
		mock = mock,

		start = function (schema: Volt.Schema): Volt.Runtime
			if schema.side == SERVER then
				return Volt.start(schema, mock.server)
			end

			local _, transport: Volt.Transport = mock:join(PLAYER)

			return Volt.start(schema, transport)
		end,
	}
end

-- Names what a require was given, an instance by its class and path
local function describe(target: any): string
	if typeof(target) == "Instance" then
		return `the {target.ClassName} {target:GetFullName()}`
	end

	return `the {typeof(target)} {target}`
end

--[[
    Runs a ModuleScript's file once per environment with script set to it,
    as require does in Roblox, and errors naming anything else it is given
--]]

local function load(state: State, target: any): any
	local record: Module? = state.modules[target]
	if not record then
		error(`require could not resolve {describe(target)}, which no mounted file or override answers`, 3)
	elseif record.loaded then
		return record.result
	elseif record.loading then
		error(`{record.path} was required while it was still loading`, 3)
	end

	local scope: { [string]: any } = table.clone(state.globals)
	scope.script = target

	local chunk: (...any) -> ...any = luau.load(Sources[record.path], { debugName = record.path, environment = scope })

	record.loading = true
	local results: { n: number, [number]: any } = table.pack(pcall(chunk))
	record.loading = false

	if not results[1] then
		error(`{record.path} threw while loading: {results[2]}`, 0)
	elseif results.n ~= 2 then
		error(`{record.path} returned {results.n - 1} values, where a module returns exactly one`, 0)
	end

	record.loaded = true
	record.result = results[2]

	return results[2]
end

local function create(className: string, name: string, parent: any): any
	local instance: any = roblox.Instance.new(className)
	instance.Name = name
	instance.Parent = parent

	return instance
end

local function addFile(state: State, path: string, name: string, parent: any): any
	local module: any = create("ModuleScript", name, parent)

	if not Sources[path] then
		Sources[path] = fs.readFile(path)
	end

	state.modules[module] = { path = path, loading = false, loaded = false, result = nil }
	state.paths[path] = module

	return module
end

--[[
    Mounts a folder as Rojo maps it: a ModuleScript when it holds an
    init.luau, else a Folder, with each .luau file in it a ModuleScript and
    each folder in it mounted the same way
--]]

local function mount(state: State, directory: string, name: string, parent: any)
	local init: string = `{directory}/{INIT}`
	local instance: any

	if fs.isFile(init) then
		instance = addFile(state, init, name, parent)
	else
		instance = create("Folder", name, parent)
	end

	for _, entry: string in fs.readDir(directory) do
		local path: string = `{directory}/{entry}`
		local stem: string? = entry:match(MODULE_FILE)

		if fs.isDir(path) then
			mount(state, path, entry, instance)
		elseif stem and entry ~= INIT then
			addFile(state, path, stem, instance)
		end
	end
end

--[[
    The ModuleScript at a dotted path from a service, as GetFullName writes
    it, made with any folder on the way when nothing is mounted there
--]]

local function place(dataModel: any, path: string): any
	local segments: { string } = path:split(".")
	assert(#segments > 1, `The override {path} names no module inside a service`)

	local current: any = dataModel:GetService(table.remove(segments, 1) :: string)
	local last: string = table.remove(segments) :: string

	for _, segment: string in segments do
		current = current:FindFirstChild(segment) or create("Folder", segment, current)
	end

	local found: any = current:FindFirstChild(last)
	if not found then
		return create("ModuleScript", last, current)
	end

	assert(found:IsA("ModuleScript"), `The override {path} names a {found.ClassName}, which require cannot take`)

	return found
end

--[[
    Loads one .luau file by its repo-relative path in a fresh environment
    and returns what it returns. Each override answers the require of the
    ModuleScript at its dotted path, such as ReplicatedStorage.Packages.Volt,
    with its value, in place of what is mounted there or where nothing is
--]]

function Environment.load(path: string, overrides: { [string]: any }?): any
	local dataModel: any = roblox.Instance.new("DataModel")
	local state: State = { modules = {}, paths = {}, globals = {} }

	state.globals = {
		game = dataModel,
		task = task,

		require = function (target: any): any
			return load(state, target)
		end,
	}

	-- The Roblox datatypes and Instance, which Lune's library holds under the names Roblox gives them
	for name: string, value: any in roblox do
		if name:match("^%u") then
			state.globals[name] = value
		end
	end

	state.globals.OverlapParams = OverlapParams

	Heartbeats[dataModel:GetService("RunService")] = heartbeat()

	local packages: any = create("Folder", "Packages", dataModel:GetService("ReplicatedStorage"))

	if fs.isDir(SOURCE) then
		mount(state, SOURCE, PACKAGE, packages)
	end

	if fs.isDir(FIXTURES) then
		mount(state, FIXTURES, FIXTURES_NAME, dataModel:GetService("ServerScriptService"))
	end

	addFile(state, promiseSource, "Promise", packages)

	local volt: any = create("ModuleScript", "Volt", packages)
	state.modules[volt] = { path = "Volt's stand-in", loading = false, loaded = true, result = voltStandIn() }

	for target: string, value: any in overrides or {} do
		state.modules[place(dataModel, target)] =
			{ path = `the override at {target}`, loading = false, loaded = true, result = value }
	end

	local module: any = state.paths[path]
	if not module then
		error(`{path} is no file this environment mounts; it loads the .luau files under {SOURCE} and {FIXTURES}`, 2)
	end

	return load(state, module)
end

return Environment
