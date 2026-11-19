--[[
    The client handle's cases' rig: Tread's client started as the local
    player of a fresh game, over the rig pool's stand-in and Frontier
    Zero's tables, with the server's half of Tread's scope on Volt's mock
--]]

--!strict
local roblox: any = require("@lune/roblox") -- Its typedefs leave out the datatypes and implementProperty

local Environment = require("../../Environment")
local Pool = require("./Pool")

local GLOBALS: string = "tests/Fixtures/Environment/Globals.luau"
local RIGS: string = "ReplicatedStorage.Packages.Tread.Client.Rigs" -- Where the handle requires its rig pool
local PLAYER: string = "Player" -- The local player's name, as the mock joins its client
local STEPS: number = 3 -- Mock steps a flushed send takes to reach the other side's listener
local SERVER_TICK: number = 100 -- The server tick the handshake names
local WIRE: number = 2 ^ 16 -- The values a block's u16 sequence and tick hold
local BUFFER_BYTES: number = 128 -- Past the largest OwnerState

-- What the device says of itself, as GuiService and UserInputService give it
export type Device = {
	tenFoot: boolean,
	touch: boolean,
	keyboard: boolean,
	display: string, -- An Enum.DisplaySize name
}

export type Options = {
	device: Device?, -- A desktop's unless given
	start: boolean?, -- False leaves Client.start to the case
}

export type Rig = { [string]: any }

-- One RunService:BindToRenderStep call, as an environment's RunService took it
export type Binding = {
	name: string,
	priority: number,
}

local DESKTOP: Device = { tenFoot = false, touch = false, keyboard = true, display = "Large" }

-- Each environment's frame callbacks by its RunService, its ten-foot answer by its GuiService, and each kick
local Frames: { [any]: { (dt: number) -> () } } = {}
local TenFoot: { [any]: boolean } = {}
local Kicks: { [any]: string } = {}

-- Each environment's render-step bindings by its RunService, in priority order, which match the front of its frames
local Bindings: { [any]: { Binding } } = {}

-- Lune's RunService has no PreRender and its GuiService no IsTenFootInterface, so each environment answers its own
roblox.implementProperty("RunService", "PreRender", function (runService: any): any
	return {
		Connect = function (_: any, callback: (dt: number) -> ()): any
			local callbacks: { (dt: number) -> () } = Frames[runService]
			table.insert(callbacks, callback)

			return {
				Disconnect = function (_: any)
					local index: number? = table.find(callbacks, callback)
					if index then
						table.remove(callbacks, index)
					end
				end,
			}
		end,
	}
end)

-- Roblox runs every render step in priority order before any PreRender connection, so a binding joins the frames there
roblox.implementMethod(
	"RunService",
	"BindToRenderStep",
	function (runService: any, name: string, priority: number, callback: (dt: number) -> ())
		local bindings: { Binding } = Bindings[runService]
		local at: number = #bindings + 1

		for index: number, binding: Binding in bindings do
			if binding.priority > priority then
				at = index
				break
			end
		end

		table.insert(bindings, at, { name = name, priority = priority })
		table.insert(Frames[runService], at, callback)
	end
)

roblox.implementMethod("GuiService", "IsTenFootInterface", function (gui: any): boolean
	return TenFoot[gui] == true
end)

roblox.implementMethod("Player", "Kick", function (player: any, message: string)
	Kicks[player] = message
end)

-- A copy all the way down, since the handle and the interpolation refill their own tables
local function copy(value: any): any
	if type(value) ~= "table" then
		return value
	end

	local made: { [any]: any } = {}
	for key: any, inner: any in value do
		made[key] = copy(inner)
	end

	return made
end

local Handle = {}

--[[
    A rig with the client started, its handshake flushed to the server,
    and nothing from the server sent yet, unless the options leave the
    start to the case
--]]

function Handle.new(options: Options?): Rig
	local given: Options = options or {}
	local device: Device = given.device or DESKTOP
	local pool: any = Pool.new()

	local globals: any = Environment.load(GLOBALS, { [RIGS] = pool.module })
	local dataModel: any = globals.game
	local packages: any = dataModel:GetService("ReplicatedStorage").Packages
	local tread: any = packages.Tread

	local player: any = roblox.Instance.new("Player")
	player.Name = PLAYER
	dataModel:GetService("Players").LocalPlayer = player

	local input: any = dataModel:GetService("UserInputService")
	input.TouchEnabled = device.touch
	input.KeyboardEnabled = device.keyboard

	local gui: any = dataModel:GetService("GuiService")
	gui.ViewportDisplaySize = roblox.Enum.DisplaySize[device.display]
	TenFoot[gui] = device.tenFoot

	local frames: { (dt: number) -> () } = {}
	Frames[dataModel:GetService("RunService")] = frames

	local bindings: { Binding } = {}
	Bindings[dataModel:GetService("RunService")] = bindings

	-- The server first, so the player the client joins as is one it hears join
	local server: any = globals.require(tread.Network.Server)
	local mock: any = globals.require(packages.Volt).mock

	local Block: any = globals.require(tread.Codec.Block)
	local Config: any = globals.require(tread.Config)
	local Constants: any = globals.require(tread.Constants)
	local Fields: any = globals.require(tread.Codec.Fields)
	local OwnerState: any = globals.require(tread.Codec.OwnerState)
	local Record: any = globals.require(tread.Codec.Record)
	local Reliable: any = globals.require(tread.Codec.Reliable)
	local State: any = globals.require(tread.Step.State)
	local StateWord: any = globals.require(tread.Codec.StateWord)
	local Example: any = globals.require(dataModel:GetService("ServerScriptService").Fixtures.Config.Example)

	local shared: any = Example.shared()
	local client: any = Example.client()
	local layout: any = Fields.compile(shared.fields)
	local limits: any = { lean = shared.step.lean, headCone = shared.step.headCone }

	local rig: Rig = {
		globals = globals,
		tread = tread,
		pool = pool,
		player = player,
		server = server,
		mock = mock,
		shared = shared,
		client = client,
		State = State,
		Constants = Constants,
		Client = globals.require(tread.Client),
		Predict = globals.require(tread.Client.Predict),
		Interpolate = globals.require(tread.Client.Interpolate),
		moves = {} :: { { [string]: any } },
		bindings = bindings, -- Every render-step binding made in the environment, in priority order
		sequence = 0,
	}

	-- The game's input sample, its declared fields at rest, and a level look ahead
	client.sample = function (command: any)
		command.fields.slot = 0
		command.fields.shots = {}
	end

	server.Move.on(
		function (_: any, command: number, acknowledged: number, received: number, delay: number, commands: any)
			table.insert(rig.moves, {
				command = command,
				acknowledged = acknowledged,
				received = received,
				delay = delay,
				count = #commands,
			})
		end
	)

	function rig.step()
		for _ = 1, STEPS do
			mock:step()
		end
	end

	function rig.start(): any
		rig.handle = rig.Client.start(shared, client)
		rig.step()

		return rig.handle
	end

	-- Fires a server-to-client message at the local player, flushes it and lets it arrive
	function rig.send(name: string, ...: any)
		server[name].fire(mock.players[1], ...)
		server.flush()
		rig.step()
	end

	-- The server's handshake, with the shared table's own hash unless another is given
	function rig.handshake(hash: number?)
		rig.send("Shared", hash or Config.hash(shared), SERVER_TICK)
	end

	-- Slot table entries, each { slot, generation, rig?, player? }, a rig of nil freeing the slot
	function rig.slots(list: { { [string]: any } })
		local entries: { any } = {}

		for _, spec: { [string]: any } in list do
			local entry: { [string]: any } = { slot = 0, taken = nil }
			Reliable.write(entry, spec.slot, spec.generation, spec.rig, spec.player)
			table.insert(entries, entry)
		end

		rig.send("Slots", entries)
	end

	-- The local player's own slot taken
	function rig.own(slot: number, generation: number)
		rig.slots({ { slot = slot, generation = generation, rig = "A", player = player } })
	end

	-- A step state at rest where the server says the body is, after the command and on the tick given
	function rig.body(position: vector, command: number, tick: number): any
		local state: any = State.new()
		state.position = position
		state.command = command
		state.tick = tick
		state.fields = { beingRevived = false }
		state.block = { sinceJump = 0, sinceShot = 15 }

		return state
	end

	-- An OwnerState of a state, its buffer exactly as long as Volt hands it over
	function rig.owner(state: any, depth: number?)
		local scratch: buffer = buffer.create(BUFFER_BYTES)
		state.depth = depth or 1
		local length: number = OwnerState.write(state, scratch, 0, layout, limits)
		local data: buffer = buffer.create(length)
		buffer.copy(data, 0, scratch, 0, length)

		rig.send("Owner", data)
	end

	-- A death message: the dying slot and generation, the body's, and the push's direction
	function rig.death(slot: number, generation: number, body: number, bodyGeneration: number, push: vector)
		local character: number, lying: number, pushX: number, pushY: number, pushZ: number =
			Reliable.writeDeath(slot, generation, body, bodyGeneration, push)

		rig.send("Death", character, lying, pushX, pushY, pushZ)
	end

	-- A state word for a record, every field at rest but those given
	function rig.word(fields: { [string]: any }): number
		local word: { [string]: any } = {
			mode = "Ground",
			posture = "Stand",
			sprint = false,
			aim = false,
			waterLevel = "Dry",
			jumps = 0,
			lands = 0,
			heavy = false,
			epoch = 0,
		}

		for name: string, value: any in fields do
			word[name] = value
		end

		return StateWord.pack(word)
	end

	--[[
	    Sends one relay block. Its tick is required and its sequence counts
	    up from 1. Reveals and hides are { slot, generation, kind }; looks
	    are { slot, generation, outfit?, held? }; records are Record fields
	    by name, every one but slot, generation and position optional;
	    footsteps are Block's
	--]]

	function rig.relay(spec: { [string]: any })
		local block: any = Block.new()
		rig.sequence += 1
		block.sequence = rig.sequence % WIRE
		block.tick = spec.tick % WIRE

		local reveals: { any } = spec.reveals or {}
		local hides: { any } = spec.hides or {}
		block.reveals, block.revealCount = reveals, #reveals
		block.hides, block.hideCount = hides, #hides

		local looks: { any } = spec.looks or {}
		local partBytes: number = Constants.MAX_LOOK + Constants.MAX_HELD
		local parts: buffer = buffer.create(math.max(#looks, 1) * partBytes)

		for index: number, look: { [string]: any } in looks do
			local at: number = (index - 1) * partBytes
			local entry: { [string]: any } = {
				slot = look.slot,
				generation = look.generation,
				look = false,
				lookData = parts,
				lookAt = at,
				lookLength = 0,
				held = false,
				heldData = parts,
				heldAt = at + Constants.MAX_LOOK,
				heldLength = 0,
			}

			if look.outfit then
				entry.look = true
				entry.lookLength = Fields.write(layout.slot, look.outfit, parts, at)
			end

			if look.held then
				entry.held = true
				entry.heldLength = Fields.write(layout.held, look.held, parts, at + Constants.MAX_LOOK)
			end

			block.looks[index] = entry
		end

		block.lookCount = #looks

		local records: { any } = spec.records or {}
		local recordData: buffer = buffer.create(math.max(#records, 1) * Constants.RECORD_BYTES)

		for index: number, fields: { [string]: any } in records do
			local record: { [string]: any } = Record.new()
			for name: string, value: any in fields do
				record[name] = value
			end

			Record.write(record, recordData, (index - 1) * Constants.RECORD_BYTES, limits)
			block.records[index] = (index - 1) * Constants.RECORD_BYTES
		end

		block.recordData, block.recordCount = recordData, #records

		local steps: { any } = spec.footsteps or {}
		local stepData: buffer = buffer.create(math.max(#steps, 1) * Constants.FOOTSTEP_BYTES)

		for index: number, step: any in steps do
			Block.writeFootstep(step, stepData, (index - 1) * Constants.FOOTSTEP_BYTES)
			block.footsteps[index] = (index - 1) * Constants.FOOTSTEP_BYTES
		end

		block.footstepData, block.footstepCount = stepData, #steps

		local data: buffer = buffer.create(Constants.MAX_RELAY_BYTES)
		local bytes: number = Block.write(block, data)
		local exact: buffer = buffer.create(bytes)
		buffer.copy(exact, 0, data, 0, bytes)

		rig.send("Relay", exact)
	end

	-- Runs frames of the seconds given each, a simulation tick's unless given
	function rig.frames(count: number, dt: number?)
		for _ = 1, count do
			for _, callback: (dt: number) -> () in table.clone(frames) do
				callback(dt or 1 / shared.rates.simulation)
			end
		end
	end

	-- The message the local player was kicked with, nil while it hasn't been
	function rig.kicked(): string?
		return Kicks[player]
	end

	rig.copy = copy

	if given.start ~= false then
		rig.start()
	end

	return rig
end

return Handle
