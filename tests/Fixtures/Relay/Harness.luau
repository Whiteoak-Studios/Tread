--[[
    The relay cases' harness: the relay started on the example game's tables,
    bodies in the slot table, and viewers whose clients read every block they
    are sent, the first of them over Volt.mock and Tread's generated modules
--]]

--!strict
local Harness = {}
Harness.__index = Harness

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Packages = ReplicatedStorage.Packages

local Tread = Packages.Tread
local Block = require(Tread.Codec.Block)
local Constants = require(Tread.Constants)
local Example = require(ServerScriptService.Fixtures.Config.Example)
local Fields = require(Tread.Codec.Fields)
local Record = require(Tread.Codec.Record)
local Relay = require(Tread.Server.Relay)
local Sequence = require(Tread.Codec.Sequence)
local Slots = require(Tread.Server.Slots)
local State = require(Tread.Step.State)

local MASK_BITS: number = 16 -- The sequences before the newest a client's acknowledgment covers
local WRAP: number = 2 ^ 16
local STEPS: number = 3 -- Mock steps that carry a flush across, as manualFlush.luau finds

type Kind = Slots.Kind
type State = State.State
type Values = State.Values
type Viewer = Relay.Viewer

-- A look entry as a client read it, each part present as its packed bytes
export type Look = {
	slot: number,
	generation: number,
	look: string?,
	held: string?,
}

-- What one client read in one run
export type Seen = {
	sizes: { number }, -- Each block's bytes, a lost one included
	lost: number,
	sequences: { number }, -- Each block's sequence, a lost one's left out
	reveals: { Block.Reveal },
	hides: { Block.Hide },
	looks: { Look },
	footsteps: { Block.Footstep },
	records: { Record.Record },
	blocks: { { reveals: { number }, looks: { number }, records: { number } } }, -- The slots in each block read
}

-- One simulated viewer's client
export type Client = {
	viewer: Viewer,
	lose: number, -- The blocks still to come that are lost in transit
	lag: number, -- The runs its acknowledgment takes to reach the relay, 0 for at once
	sent: { { newest: number, mask: number } }, -- The acknowledgments on their way, oldest first
	newest: number, -- The newest sequence read, 0 for none
	received: { [number]: boolean },
	drawn: { [number]: { generation: number, kind: Block.Kind } }, -- What it draws, by slot, from reveals and hides
	seen: Seen,
}

type Network = {
	server: any,
	client: any,
	mock: any,
	player: any,
}

type Fields = {
	layout: Fields.Layout,
	limits: { lean: number, headCone: number },
	states: { [number]: State },
	commands: { [number]: State.Command },
	viewers: { Viewer },
	clients: { [any]: Client },
	hidden: { [any]: { [number]: boolean } },
	traffic: number,
	tick: number,
	network: Network?,
}

local function seen(): Seen
	return {
		sizes = {},
		lost = 0,
		sequences = {},
		reveals = {},
		hides = {},
		looks = {},
		footsteps = {},
		records = {},
		blocks = {},
	}
end

--[[
    A harness with the relay started on the example's shared and server
    tables, which tweak may change first, every viewer's traffic at the
    harness's own count and anti-ESP hiding whatever hide asks. With
    network, the first viewer is the mock's player and its blocks cross
    Volt.mock
--]]

function Harness.new(network: boolean?, tweak: ((shared: any, server: any) -> ())?): Self
	local shared = Example.shared()
	local server = Example.server()
	if tweak then
		tweak(shared, server)
	end

	local layout: Fields.Layout = Fields.compile(shared.fields)

	Slots.start(server.slots.reserve)

	local self: Self = setmetatable({
		layout = layout,
		limits = { lean = shared.step.lean, headCone = shared.step.headCone },
		states = {} :: { [number]: State },
		commands = {} :: { [number]: State.Command },
		viewers = {} :: { Viewer },
		clients = {} :: { [any]: Client },
		hidden = {} :: { [any]: { [number]: boolean } },
		traffic = 0,
		tick = 0,
		network = nil :: Network?,
	}, Harness)

	Relay.start({ shared = shared, server = server, layout = layout }, function (key: any, data: buffer)
		self:_deliver(key, data)
	end, function (_: any): number
		return self.traffic
	end, function (viewer: Viewer, slot: number): boolean
		local hidden: { [number]: boolean }? = self.hidden[viewer.key]

		return hidden ~= nil and hidden[slot] == true
	end)

	if network then
		-- The server first, so the player the client joins as is one it hears join
		local serverNetwork: any = require(Tread.Network.Server)
		local clientNetwork: any = require(Tread.Network.Client)
		local mock: any = require(Packages.Volt).mock

		clientNetwork.flush()
		for _ = 1, STEPS do
			mock:step()
		end

		local player: any = mock.players[1]
		self.network = { server = serverNetwork, client = clientNetwork, mock = mock, player = player }

		clientNetwork.Relay.on(function (data: buffer)
			self:_receive(player, data)
		end)
	end

	return self
end

--[[
    A new viewer with no character at the origin: the mock's player for the
    first one on a network harness, else a key of its own
--]]

function Harness.viewer(self: Self, name: string): Client
	local network: Network? = self.network
	local key: any = { Name = name }
	if network and #self.viewers == 0 then
		key = network.player
	end

	local viewer: Viewer = { key = key, slot = nil, position = vector.zero, acknowledged = 0, received = 0 }
	local client: Client = {
		viewer = viewer,
		lose = 0,
		lag = 0,
		sent = {},
		newest = 0,
		received = {},
		drawn = {},
		seen = seen(),
	}

	table.insert(self.viewers, viewer)
	self.clients[key] = client
	self.hidden[key] = {}

	return client
end

--[[
    A body of a kind standing at a place in a slot of its own, with its
    entry set and a resting state on the ground
--]]

function Harness.spawn(self: Self, kind: Kind, position: vector): number
	local slot: number? = Slots.take(kind)
	if slot == nil then
		error(`No slot was free for a {kind}`)
	end

	Slots.setEntry(slot, { kind = kind, rig = "A" })

	local state: State = State.new()
	state.position = position
	state.mode = "Ground"
	state.grounded = true
	state.groundMaterial = Enum.Material.Grass
	self.states[slot] = state

	return slot
end

-- Takes a body out of the states and frees its slot
function Harness.despawn(self: Self, slot: number)
	self.states[slot] = nil
	self.commands[slot] = nil
	Slots.release(slot)
end

-- Sets whether anti-ESP hides a slot from a viewer
function Harness.hide(self: Self, client: Client, slot: number, hidden: boolean)
	self.hidden[client.viewer.key][slot] = hidden
end

--[[
    One relay tick: every client's view of the run starts empty, the relay
    runs, a network harness flushes and steps the mock, and each viewer's
    acknowledgment is what its client had read lag runs before
--]]

function Harness.run(self: Self)
	self.tick += 1

	for _, client: Client in self.clients do
		client.seen = seen()
	end

	Relay.run(self.tick, self.viewers, self.states, self.commands)

	local network: Network? = self.network
	if network then
		network.server.flush()

		for _ = 1, STEPS do
			network.mock:step()
		end
	end

	for _, client: Client in self.clients do
		local mask: number = 0

		for back: number = 1, MASK_BITS do
			if client.received[(client.newest - back) % WRAP] then
				mask += 2 ^ (back - 1)
			end
		end

		-- The acknowledgment reaches the relay lag runs after the client read what it covers
		table.insert(client.sent, { newest = client.newest, mask = mask })
		if #client.sent > client.lag then
			local arrived: { newest: number, mask: number } = table.remove(client.sent, 1) :: any
			client.viewer.acknowledged = arrived.newest
			client.viewer.received = arrived.mask
		end
	end
end

-- Runs count relay ticks
function Harness.runs(self: Self, count: number)
	for _ = 1, count do
		self:run()
	end
end

-- Hands a block to its viewer: over the mock for its player, else straight to the client as a copy of its own
function Harness._deliver(self: Self, key: any, data: buffer)
	local network: Network? = self.network
	if network and key == network.player then
		network.server.Relay.fire(key, data)

		return
	end

	self:_receive(key, buffer.fromstring(buffer.tostring(data)))
end

-- A client reads one block, unless it is one it is set to lose
function Harness._receive(self: Self, key: any, data: buffer)
	local client: Client = self.clients[key]
	local view: Seen = client.seen
	table.insert(view.sizes, buffer.len(data))

	if client.lose > 0 then
		client.lose -= 1
		view.lost += 1

		return
	end

	local block: Block.Block = Block.new()
	Block.read(data, block)

	table.insert(view.sequences, block.sequence)
	client.received[block.sequence] = true
	if client.newest == 0 or Sequence.difference(block.sequence, client.newest) > 0 then
		client.newest = block.sequence
	end

	local slots: { reveals: { number }, looks: { number }, records: { number } } =
		{ reveals = {}, looks = {}, records = {} }
	table.insert(view.blocks, slots)

	for index: number = 1, block.revealCount do
		local reveal: Block.Reveal = block.reveals[index]
		client.drawn[reveal.slot] = { generation = reveal.generation, kind = reveal.kind }
		table.insert(view.reveals, table.clone(reveal))
		table.insert(slots.reveals, reveal.slot)
	end

	for index: number = 1, block.hideCount do
		local hide: Block.Hide = block.hides[index]
		local drawn: { generation: number, kind: Block.Kind }? = client.drawn[hide.slot]
		if drawn and drawn.generation == hide.generation then
			client.drawn[hide.slot] = nil
		end

		table.insert(view.hides, table.clone(hide))
	end

	for index: number = 1, block.lookCount do
		local look: Block.Look = block.looks[index]
		local read: Look = { slot = look.slot, generation = look.generation }

		if look.look then
			read.look = buffer.readstring(data, look.lookAt, look.lookLength)
		end

		if look.held then
			read.held = buffer.readstring(data, look.heldAt, look.heldLength)
		end

		table.insert(view.looks, read)
		table.insert(slots.looks, look.slot)
	end

	for index: number = 1, block.footstepCount do
		local step: Block.Footstep = { at = vector.zero, kind = "Walk", material = Enum.Material.Air }
		Block.readFootstep(data, block.footsteps[index], step)
		table.insert(view.footsteps, step)
	end

	for index: number = 1, block.recordCount do
		local record: Record.Record = Record.new()
		Record.read(data, block.records[index], record, self.limits)
		table.insert(view.records, record)
		table.insert(slots.records, record.slot)
	end
end

--[[
    The packed bytes of a look or a held item, as a look entry carries them
--]]

function Harness.pack(self: Self, list: "slot" | "held", values: Values): string
	local data: buffer = buffer.create(Constants.MAX_LOOK)
	local length: number = Fields.write(self.layout[list], values, data, 0)

	return buffer.readstring(data, 0, length)
end

-- The first of a list's entries that names a slot, or nil
function Harness.find(entries: { any }, slot: number): any
	for _, entry: any in entries do
		if entry.slot == slot then
			return entry
		end
	end

	return nil
end

-- How many of a list's entries name a slot
function Harness.count(entries: { { slot: number } }, slot: number): number
	local count: number = 0

	for _, entry: { slot: number } in entries do
		if entry.slot == slot then
			count += 1
		end
	end

	return count
end

Harness.Relay = Relay
Harness.Slots = Slots

export type Harness = Self
type Self = typeof(setmetatable({} :: Fields, Harness))

return Harness
