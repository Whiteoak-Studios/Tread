--[[
    The anti-ESP cases' harness: anti-ESP started on the example's tables
    over a world with no surfaces, bodies in the slot table, bot viewers,
    and walls a case sets, which log every ray anti-ESP casts
--]]

--!strict
local Harness = {}
Harness.__index = Harness

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Tread = ReplicatedStorage.Packages.Tread
local AntiEsp = require(Tread.Server.AntiEsp)
local Config = require(Tread.Config)
local Connections = require(Tread.Server.Connections)
local Constants = require(Tread.Constants)
local Engine = require(Tread.Step.Engine)
local Example = require(ServerScriptService.Fixtures.Config.Example)
local Eye = require(Tread.Step.Eye)
local Relay = require(Tread.Server.Relay)
local Slots = require(Tread.Server.Slots)
local State = require(Tread.Step.State)
local World = require(Tread.Step.World)

local SLOTS: number = Constants.SLOTS
local RTT: number = 0.2 -- Every bot viewer's round trip, inside the example's look-ahead clamp
local BUDGET: number = 1 -- Seconds a slice may take, more than any case's due tests need
local TOLERANCE: number = 1e-6 -- Studs a logged ray's end may sit from a point and still end there

type ServerSettings = Config.ServerSettings
type Shared = Config.Shared
type Kind = Slots.Kind
type State = State.State
type Viewer = Relay.Viewer
type World = State.World
type Wall = (origin: vector, direction: vector) -> boolean

-- One ray anti-ESP cast, with where it ends
export type Ray = {
	origin: vector,
	direction: vector,
	to: vector,
}

type Fields = {
	shared: Shared,
	server: ServerSettings,
	world: World,
	states: { [number]: State },
	rays: { Ray }, -- Every ray cast since the last slice began
	wall: Wall, -- What each ray meets, true for an occluder
}

-- Walls nowhere, and walls everywhere
function Harness.open(_: vector, _: vector): boolean
	return false
end

function Harness.solid(_: vector, _: vector): boolean
	return true
end

--[[
    A harness with anti-ESP started on the example's tables, which tweak
    may change first, every bot's round trip at RTT and no walls. The world
    has no surfaces, so every eye is the eased eye where it stands
--]]

function Harness.new(tweak: ((shared: Shared, server: ServerSettings) -> ())?): Self
	local shared: Shared = Example.shared()
	local server: ServerSettings = Example.server()
	server.bots = { rtt = RTT }

	if tweak then
		tweak(shared, server)
	end

	Slots.start(server.slots.reserve)
	Connections.start(server.rewind.rttSmoothing, server.bots)

	local world: World = World.new(
		shared.step,
		shared.rates.simulation,
		Engine.casts(shared.collision),
		shared.water,
		shared.rules,
		true
	)

	local self: Self = setmetatable({
		shared = shared,
		server = server,
		world = world,
		states = {} :: { [number]: State },
		rays = {} :: { Ray },
		wall = Harness.open :: Wall,
	}, Harness)

	local function blocked(origin: vector, direction: vector): boolean
		table.insert(self.rays, { origin = origin, direction = direction, to = origin + direction })

		return self.wall(origin, direction)
	end

	AntiEsp.start({ shared = shared, server = server }, world, self.states, blocked)

	return self
end

--[[
    A body of a kind standing on the ground at a place, facing a yaw, in a
    slot of its own with its entry set and its eye at the standing height
--]]

function Harness.body(self: Self, kind: Kind, position: vector, facing: number?): number
	local slot: number? = Slots.take(kind)
	if slot == nil then
		error(`No slot was free for a {kind}`)
	end

	Slots.setEntry(slot, { kind = kind, rig = "A" })

	local state: State = State.new()
	state.position = position
	state.facing = facing or 0
	state.mode = "Ground"
	state.grounded = true
	state.eyeHeight = self.shared.step.eyeStanding
	self.states[slot] = state

	return slot
end

--[[
    A bot viewer, whose connection reports RTT. With a slot it is that
    body's viewer, measured from where the body stands, and with none from
    the origin
--]]

function Harness.viewer(self: Self, name: string, slot: number?): Viewer
	local key: { Name: string } = { Name = name }
	Connections.add(key)

	local position: vector = vector.zero
	if slot ~= nil then
		position = self.states[slot].position
	end

	return { key = key, slot = slot, position = position, acknowledged = 0, received = 0 }
end

-- A player standing at a place and the viewer it is
function Harness.player(self: Self, name: string, position: vector): (number, Viewer)
	local slot: number = self:body("Player", position)

	return slot, self:viewer(name, slot)
end

--[[
    Moves a body, and its viewer's place with it when it has one, as the
    server handle refills a viewer each relay tick
--]]

function Harness.move(self: Self, slot: number, position: vector, viewer: Viewer?)
	self.states[slot].position = position

	if viewer then
		viewer.position = position
	end
end

--[[
    The same slot again with a new life: it is released and every other
    free slot is taken until it comes back with its next generation, then
    the others are freed, so its body and entry stay as they were
--]]

function Harness.reborn(self: Self, slot: number): number
	local _, entry: Slots.Entry? = Slots.get(slot)
	if entry == nil then
		error(`The slot {slot} has no entry to give a new life`)
	end

	local kind: Kind = entry.kind
	Slots.release(slot)

	local others: { number } = {}
	local generation: number? = nil

	-- Every slot is free at most once before it comes round again
	for _ = 1, SLOTS do
		local taken: number?, life: number? = Slots.take(kind)
		if taken == slot then
			generation = life
			break
		elseif taken ~= nil then
			table.insert(others, taken)
		end
	end

	for _, other: number in others do
		Slots.release(other)
	end

	if generation == nil then
		error(`The slot {slot} never came back`)
	end

	Slots.setEntry(slot, { kind = kind, rig = "A" })

	return generation
end

-- One slice at a schedule time, with every due test run unless a budget is given, and its rays logged fresh
function Harness.slice(self: Self, now: number, budget: number?)
	table.clear(self.rays)
	AntiEsp.run(budget or BUDGET, now)
end

-- How many of the logged rays end at a point
function Harness.endingAt(self: Self, point: vector): number
	local count: number = 0

	for _, ray: Ray in self.rays do
		if vector.magnitude(ray.to - point) < TOLERANCE then
			count += 1
		end
	end

	return count
end

Harness.AntiEsp = AntiEsp
Harness.Connections = Connections
Harness.Eye = Eye
Harness.Slots = Slots

export type Harness = Self
type Self = typeof(setmetatable({} :: Fields, Harness))

return Harness
