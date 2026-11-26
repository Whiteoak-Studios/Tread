--[[
    The anti-ESP cases' harness: anti-ESP started on the example's tables
    over a world with no surfaces, bodies in the slot table, bot viewers,
    and walls a case sets, of parts or not, which log every ray it casts
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
local LATE: number = 2 * BUDGET -- What a stand-in clock's late read gives, past the deadline of any slice it starts
local TOLERANCE: number = 1e-6 -- Studs a logged ray's end may sit from a point and still end there
local TICK_SLACK: number = 1e-9 -- Ticks a slice's time times the rate may fall short of its tick and still be in it

type ServerSettings = Config.ServerSettings
type Shared = Config.Shared
type Kind = Slots.Kind
type State = State.State
type Viewer = Relay.Viewer
type World = State.World
type Wall = (origin: vector, direction: vector) -> any -- An occluder's instance or true, nil or false for none

-- One ray anti-ESP cast, with where it ends
export type Ray = {
	origin: vector,
	direction: vector,
	to: vector,
}

-- A stand-in for the clock a slice's deadline is read on, which a case sets by hand
export type Clock = {
	read: () -> number, -- What anti-ESP reads: 0, then LATE from the read numbered late on
	reads: number, -- Its reads since a case last set this to 0
	late: number, -- The first read that finds the deadline passed, math.huge for none
}

type Fields = {
	shared: Shared,
	server: ServerSettings,
	world: World,
	states: { [number]: State },
	rays: { Ray }, -- Every ray cast since the last slice began
	wall: Wall, -- What each ray meets, true for an occluder
	occluded: number, -- The rays among them cast through the occluder query, which asks what a ray met, since start
	kept: number, -- Verdict memory's kept tests and box rays as remembered last read them
	boxRays: number,
}

-- Walls nowhere, and walls everywhere
function Harness.open(_: vector, _: vector): boolean
	return false
end

function Harness.solid(_: vector, _: vector): boolean
	return true
end

--[[
    A wall of the parts in a folder as the engine's raycast meets them: the
    part a ray enters first from outside, each part the box of its Size at
    its CFrame, nil when it enters none, and none for a part it starts in
--]]

function Harness.parts(folder: any): Wall
	return function (origin: vector, direction: vector): any
		local from: any = Vector3.new(origin.x, origin.y, origin.z)
		local along: any = Vector3.new(direction.x, direction.y, direction.z)
		local met: any = nil
		local nearest: number = math.huge

		for _, part: any in folder:GetChildren() do
			local cframe: any = part.CFrame
			local start: any = cframe:PointToObjectSpace(from)
			local move: any = cframe:VectorToObjectSpace(along)
			local half: any = part.Size / 2
			local enter: number = 0
			local leave: number = 1
			local inside: boolean = true

			for _, axis: string in { "X", "Y", "Z" } do
				local at: number = start[axis]
				local step: number = move[axis]
				local extent: number = half[axis]
				inside = inside and math.abs(at) < extent

				if step == 0 then
					if math.abs(at) > extent then
						leave = -1
					end
				else
					local near: number = (-extent - at) / step
					local far: number = (extent - at) / step
					enter = math.max(enter, math.min(near, far))
					leave = math.min(leave, math.max(near, far))
				end
			end

			if not inside and enter <= leave and enter < nearest then
				met = part
				nearest = enter
			end
		end

		return met
	end
end

--[[
    A stand-in clock reading 0, so no slice started on it runs past its
    deadline, until the read a case numbers late, from which on it reads
    past the deadline, as a live clock stays past it, until the case starts
    the count again
--]]

function Harness.clock(): Clock
	local clock: Clock

	clock = {
		read = function (): number
			clock.reads += 1
			if clock.reads >= clock.late then
				return LATE
			end

			return 0
		end,
		reads = 0,
		late = math.huge,
	}

	return clock
end

--[[
    A harness with anti-ESP started on the example's tables, which tweak
    may change first, every bot's round trip at RTT and no walls, on clock
    when given, os.clock otherwise. The world has no surfaces, so every eye
    is the eased eye where it stands
--]]

function Harness.new(tweak: ((shared: Shared, server: ServerSettings) -> ())?, clock: (() -> number)?): Self
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
		occluded = 0,
		kept = 0,
		boxRays = 0,
	}, Harness)

	local function blocked(origin: vector, direction: vector): any
		table.insert(self.rays, { origin = origin, direction = direction, to = origin + direction })

		return self.wall(origin, direction)
	end

	-- The same ray logged, and counted apart, as anti-ESP's ask of what a ray met
	local function occluder(origin: vector, direction: vector): any
		self.occluded += 1

		return blocked(origin, direction)
	end

	AntiEsp.start({ shared = shared, server = server }, world, self.states, blocked, occluder, clock)

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

--[[
    One slice at a schedule time, with every due test run unless a budget
    is given, and its rays logged fresh, on the server tick given, or else
    the simulation tick that time falls in
--]]

function Harness.slice(self: Self, now: number, budget: number?, tick: number?)
	table.clear(self.rays)
	AntiEsp.run(budget or BUDGET, now, tick or math.floor(now * self.shared.rates.simulation + TICK_SLACK))
end

--[[
    One slice at a schedule time on a stand-in clock started anew, whose
    read numbered late finds the deadline passed and every read after it,
    none when late is left out, on the server tick given or the one the
    time falls in
--]]

function Harness.sliceOn(self: Self, clock: Clock, now: number, late: number?, tick: number?)
	clock.reads = 0
	clock.late = late or math.huge
	self:slice(now, nil, tick)
end

--[[
    Verdict memory's kept tests and box rays since this harness's last call,
    from AntiEsp.memory's totals, which one read never takes from another
--]]

function Harness.remembered(self: Self): (number, number)
	local kept: number, boxRays: number = AntiEsp.memory()
	local newKept: number, newBoxRays: number = kept - self.kept, boxRays - self.boxRays
	self.kept = kept
	self.boxRays = boxRays

	return newKept, newBoxRays
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
