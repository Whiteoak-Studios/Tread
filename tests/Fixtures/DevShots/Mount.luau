--[[
    The shooter's cases' mount: a client handle's rig with the dev client's
    Shots and Config, the dev ballistics, the dev scope's shoot and shot
    standing in, and a seeded Random in scope, which Lune's library lacks
--]]

--!strict
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox: any = require("@lune/roblox") -- Its typedefs leave out the datatypes
local task = require("@lune/task")

local Handle = require("../Client/Handle")

local SHOTS: string = "dev/Client/Shots.luau"
local CONFIG: string = "dev/Client/Config.luau"
local BALLISTICS: string = "dev/Shared/Ballistics.luau"
local BALLISTICS_CONFIG: string = "dev/Shared/BallisticsConfig.luau"
local DATATYPE: string = "^%u" -- A name Lune's library holds a Roblox datatype, Enum or Instance under
local MODULUS: number = 2 ^ 31 - 1 -- Park and Miller's minimal standard, as the bot harness draws
local MULTIPLIER: number = 48271

-- One shot report the dev scope's shot carried, with the render time the client stood at when it went
export type Report = { sequence: number, target: number?, renderTime: number }

-- One sample the dev client made, read straight after the shooter's
export type Sampled = {
	command: { [string]: any }, -- The command table itself, which Tread reuses
	renderTime: number, -- What getRenderTime gave during the sample, before the shooter's
	shots: { { [string]: number } }, -- Copies of the shots it carried
	slot: number,
	moving: boolean, -- Whether any movement input was off rest
}

export type Mounted = {
	rig: Handle.Rig,
	Shots: any,
	shoot: (slot: number) -> (), -- The dev server's shoot reaching this client
	reports: { Report },
	sampled: { Sampled },
}

-- Options for a mount: the shooter's config in place of the dev client's, and the input sample run before it
export type Options = {
	shots: { [string]: any }?,
	input: ((command: { [string]: any }) -> ())?,
}

local function create(className: string, name: string, parent: any): any
	local instance: any = roblox.Instance.new(className)
	instance.Name = name
	instance.Parent = parent

	return instance
end

-- A stand-in for Roblox's Random over Park and Miller's generator, drawing a number between two
local FakeRandom = {
	new = function (seed: number): any
		local state: number = seed % MODULUS
		if state == 0 then
			state = 1
		end

		return {
			NextNumber = function (_: any, min: number, max: number): number
				state = state * MULTIPLIER % MODULUS

				return min + (max - min) * (state - 1) / (MODULUS - 1)
			end,
		}
	end,
}

local Mount = {}

--[[
    A started rig whose input sample runs the options' input, reads the
    render time, then runs the shooter's sample and keeps what it left, with
    the shooter started on the handle. Nothing from the server is sent yet
--]]

function Mount.new(options: Options?): Mounted
	local given: Options = options or {}
	local rig: Handle.Rig = Handle.new({ start = false })
	local dataModel: any = rig.globals.game
	local replicated: any = dataModel:GetService("ReplicatedStorage")

	local files: { [any]: string } = {}
	local results: { [any]: any } = {}
	local reports: { Report } = {}
	local sampled: { Sampled } = {}
	local listener: ((slot: number) -> ())? = nil

	local shared: any = replicated:FindFirstChild("Shared") or create("Folder", "Shared", replicated)
	local dev: any = create("Folder", "Dev", shared)
	files[create("ModuleScript", "Ballistics", dev)] = BALLISTICS
	files[create("ModuleScript", "BallisticsConfig", dev)] = BALLISTICS_CONFIG

	-- The dev scope's client module, standing in with the two events the shooter uses
	local network: any = create("Folder", "Network", shared)
	results[create("ModuleScript", "Client", network)] = {
		shoot = {
			on = function (callback: (slot: number) -> ()): () -> ()
				listener = callback

				return function ()
					listener = nil
				end
			end,
		},

		shot = {
			fire = function (sequence: number, target: number?)
				table.insert(reports, { sequence = sequence, target = target, renderTime = rig.handle:getRenderTime() })
			end,
		},
	}

	local scripts: any = rig.player:FindFirstChildOfClass("PlayerScripts")
		or create("PlayerScripts", "PlayerScripts", rig.player)
	local client: any = create("Folder", "Client", scripts)
	local config: any = create("ModuleScript", "Config", client)
	local shots: any = create("ModuleScript", "Shots", client)
	files[config] = CONFIG
	files[shots] = SHOTS

	local function load(target: any): any
		local result: any = results[target]
		if result ~= nil then
			return result
		end

		local path: string? = files[target]
		if not path then
			return rig.globals.require(target)
		end

		local scope: { [string]: any } = { game = dataModel, script = target, require = load, task = task }
		for name: string, value: any in roblox do
			if name:match(DATATYPE) then
				scope[name] = value
			end
		end

		scope.Random = FakeRandom

		local chunk: () -> any = luau.load(fs.readFile(path), { debugName = path, environment = scope })
		results[target] = chunk()

		return results[target]
	end

	local shotsConfig: { [string]: any }? = given.shots
	if shotsConfig then
		load(config).shots = shotsConfig
	end

	local Shots: any = load(shots)
	local input: (command: { [string]: any }) -> () = given.input or rig.client.sample

	rig.client.sample = function (command: { [string]: any })
		input(command)

		local renderTime: number = rig.handle:getRenderTime()
		Shots.sample(command)

		local copies: { { [string]: number } } = {}
		for _, shot: { [string]: number } in command.fields.shots or {} do
			table.insert(copies, table.clone(shot))
		end

		local moving: boolean = command.forward ~= 0
			or command.right ~= 0
			or command.jump
			or command.crouch
			or command.sprint
			or command.lean ~= 0

		table.insert(sampled, {
			command = command,
			renderTime = renderTime,
			shots = copies,
			slot = command.fields.slot,
			moving = moving,
		})
	end

	rig.start()
	Shots.start(rig.handle, rig.shared)

	return {
		rig = rig,
		Shots = Shots,
		reports = reports,
		sampled = sampled,

		shoot = function (slot: number)
			local callback: ((slot: number) -> ())? = listener
			if not callback then
				error("Nothing listens to the dev scope's shoot")
			end

			callback(slot)
		end,
	}
end

return Mount
