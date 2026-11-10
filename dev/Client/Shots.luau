--[[
    G7's shooter: while the dev server's shoot names a hotbar slot, sampled
    commands fire fixture shots at the characters Tread draws, and the
    shooter's own view flies each bullet and reports what it struck
--]]

--!strict
--!native
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Packages = ReplicatedStorage.Packages
local Player = Players.LocalPlayer

local Tread = require(Packages.Tread)

local Network = require(ReplicatedStorage.Shared.Network.Client)

local Ballistics = require(ReplicatedStorage.Shared.Dev.Ballistics)
local Constants = require(Packages.Tread.Constants)
local Engine = require(Packages.Tread.Step.Engine)
local Public = require(Packages.Tread.Step.Public)
local Shapes = require(Packages.Tread.Step.Shapes)
local State = require(Packages.Tread.Step.State)

-- Requiring it finds the module Tread's client already started, as the hitboxes do
local Interpolate = require(Packages.Tread.Client.Interpolate)

local ShotsConfig = require(script.Parent.Config).shots

local EVERY: number = ShotsConfig.every
local SPREAD: number = ShotsConfig.spread
local SEED: number = ShotsConfig.seed
local LEAD: boolean = ShotsConfig.lead
local WEAPONS: { Weapon } = require(ReplicatedStorage.Shared.Dev.BallisticsConfig).weapons
local FRACTION_STEPS: number = require(ReplicatedStorage.Shared.Dev.BallisticsConfig).fractionSteps
local ANGLE_STEPS: number = Constants.ANGLE_STEPS -- A shot's packed yaw and pitch step through a turn in these
local RADIANS_PER_STEP: number = 2 * math.pi / ANGLE_STEPS
local TURN: number = 2 * math.pi
local RENDER_TICKS: number = 2 ^ 16 -- A shot's renderTick holds the low 16 bits of its render tick
local SEQUENCES: number = 2 ^ 6 -- The values a shot's 6-bit sequence holds, as the dev table declares it
local COUNTER_WRAP: number = 2 ^ 16 -- The run's counter is a u16
local STOP: number = 0 -- The slot shoot names to stop firing
local CLASS: number = 0 -- The keyboard-and-mouse input class, which no fixture reads
local NO_OFFSET: number = 0 -- A shot leaves along its own look, with no head offset to turn or hold to a cone

type GameShapes = index<index<Tread.Shared, "hitShapes">, "Stand"> -- One posture's, as the shared table gives them
type Placed = Shapes.Placed
type Posture = State.Posture
type Slot = Tread.Slot
type Weapon = Ballistics.Weapon

-- A shot as the dev table declares it
type Shot = {
	sequence: number,
	class: number,
	renderTick: number,
	fraction: number,
	yaw: number,
	pitch: number,
}

-- One posture's placed shapes crossed to Vector3, which the capsule test reads
type Crossed = {
	body: Tread.Shape,
	zones: { [string]: Tread.Shape },
}

-- A bullet in flight on the shooter's own view, its values its own, since Tread reads a command's fields back
type Flight = {
	counter: number, -- The run's counter when it was fired
	position: Vector3, -- Where its next segment starts
	direction: Vector3,
	weapon: Weapon?, -- nil for a slot with no fixture weapon, which misses at once as the server's does
	flown: number, -- Studs it has flown
	due: number, -- The render time its next segment is tested at, relay ticks
}

local Running: Tread.Client? = nil
local SimulationRate: number = 0 -- Ticks a second, from the shared table at start
local RelayRate: number = 0

local Postures: { [Posture]: Shapes.Shapes } = {} -- The shared table's hit shapes, crossed at start
local Placings: { [Posture]: Placed } = {} -- What each posture's shapes are placed into for the target being tested
local Crossings: { [Posture]: Crossed } = {} -- Each placing crossed to Vector3
local Spawned: { [number]: Slot } = {} -- Each slot client:onSpawned named and client:onDespawned hasn't ended
local Order: { number } = {} -- The drawn slots in id order, refilled at each shot's pick

local Firing: number = STOP -- The hotbar slot shoot named, STOP while not firing
local Counter: number = 0 -- The run's u16 counter, from 0 at each shoot
local Since: number = 0 -- Samples since the last shot
local Last: number = -1 -- The slot the last shot was aimed at, which the next pick goes round from
local Aim: Random = Random.new(SEED) -- What each shot's throw is drawn from, seeded again at each shoot
local Flights: { Flight } = {}
local Frame: RBXScriptConnection? = nil -- Connected only while a bullet flies or firing is on

local Pose: State.State = State.new() -- A target's drawn state, which each pose rewrites

local Shots = {}

-- A placed shape's points crossed to Vector3, into a shape of the same zone
local function cross(shape: Shapes.Shape, into: Tread.Shape)
	into.from = Engine.toVector3(shape.from)
	into.to = Engine.toVector3(shape.to)
	into.radius = shape.radius
end

-- Places a target's posed state's shapes, its feet moved back to a segment's time, and gives them crossed
local function placed(slot: Slot, feet: vector): Crossed
	local posture: Posture = Shapes.posture(Pose.posture, Pose.mode, slot.kind == "Sleeper")
	local placing: Placed = Placings[posture]
	local crossing: Crossed = Crossings[posture]
	Shapes.place(Postures[posture], placing, feet, Pose.facing, Pose.lean)

	cross(placing.body, crossing.body)
	for name: string, shape: Shapes.Shape in placing.zones do
		cross(shape, crossing.zones[name])
	end

	return crossing
end

--[[
    The shooter's view's hit test on its own: the slot of the nearest zone
    a segment meets among the drawn characters, or nil for a miss. Each is
    posed at the render time on screen and moved back along its drawn
    velocity to the segment's time, the shooter's own slot and every body
    left out, as the server's history holds no body

    @ posedAt | the render time the targets are posed at, relay ticks
    @ due | the segment's render time, relay ticks, at or before posedAt
--]]

function Shots.strike(from: Vector3, to: Vector3, posedAt: number, due: number): number?
	local move: Vector3 = to - from
	local length: number = move.Magnitude
	if length == 0 then
		return nil
	end

	local unit: Vector3 = move / length
	local back: number = (posedAt - due) / RelayRate -- Seconds
	local nearest: number? = nil
	local nearestDistance: number = math.huge

	for id: number, slot: Slot in Spawned do
		if slot.player == Player or slot.kind == "Body" or not Interpolate.pose(id, Pose) then
			continue
		end

		-- Whiteoak TODO: a rider is drawn on its platform's copy, which this view doesn't place it on, so a rider is
		-- left out; placing it as the hitboxes do brings it in once a G7 case stands a target on a platform
		if Pose.platform ~= 0 then
			continue
		end

		-- Whiteoak TODO: only the feet move back along the drawn velocity, and the facing and lean stay as drawn at
		-- posedAt; easing both back between the two records drawn between closes it if G7 shows turning targets miss
		local crossing: Crossed = placed(slot, Pose.position - Pose.velocity * back)
		local zone: string?, distance: number = Ballistics.zone(from, unit, length, crossing.body, crossing.zones)

		if zone and distance < nearestDistance then
			nearest = id
			nearestDistance = distance
		end
	end

	return nearest
end

-- Tells the dev server what a resolved bullet struck on this view, nil for a miss
local function report(flight: Flight, slot: number?)
	Network.shot.fire(flight.counter % SEQUENCES, slot)
end

--[[
    Flies a bullet's next segment as the server's fixture does, tested
    against the targets posed at a render time, and gives whether it
    resolved: on a strike, at the end of its range, or at once from a slot
    with no weapon, each reported
--]]

local function advance(flight: Flight, posedAt: number): boolean
	local weapon: Weapon? = flight.weapon
	if not weapon then
		report(flight, nil)

		return true
	end

	local travel: number = math.min(weapon.speed / SimulationRate, weapon.range - flight.flown)
	local from: Vector3 = flight.position
	local to: Vector3 = from + flight.direction * travel
	flight.position = to
	flight.flown += travel

	local slot: number? = Shots.strike(from, to, posedAt, flight.due)
	flight.due += RelayRate / SimulationRate

	if slot ~= nil then
		report(flight, slot)

		return true
	elseif flight.flown >= weapon.range then
		report(flight, nil)

		return true
	end

	return false
end

-- One drawn frame, after Tread's own: every segment whose time the render time has reached, oldest first
local function frame()
	local client: Tread.Client? = Running
	if not client then
		return
	end

	local now: number = client:getRenderTime()

	for index: number = #Flights, 1, -1 do
		local flight: Flight = Flights[index]

		while flight.due <= now do
			if advance(flight, now) then
				table.remove(Flights, index)
				break
			end
		end
	end

	-- Its connection goes once nothing flies and firing is off
	local connection: RBXScriptConnection? = Frame
	if connection and #Flights == 0 and Firing == STOP then
		connection:Disconnect()
		Frame = nil
	end
end

-- Connects the frame while anything needs it; frame itself lets it go
local function hold()
	if not Frame and (#Flights > 0 or Firing ~= STOP) then
		Frame = RunService.PreRender:Connect(frame)
	end
end

-- The dev server starts firing from a hotbar slot, or stops with STOP; a bullet already in flight still resolves
local function shoot(slot: number)
	Firing = slot

	if slot ~= STOP then
		Counter = 0
		Since = EVERY - 1 -- So the run's first sample fires
		Last = -1
		Aim = Random.new(SEED)
	end

	hold()
end

--[[
    The next drawn slot after the last one aimed at, in id order and round
    again from the lowest, posed into Pose, or nil while none is drawn. The
    shooter's own slot is never one
--]]

local function pick(): number?
	table.clear(Order)
	for id: number, slot: Slot in Spawned do
		if slot.player ~= Player then
			table.insert(Order, id)
		end
	end

	table.sort(Order)

	local start: number = 1
	for index: number, id: number in Order do
		if id > Last then
			start = index
			break
		end
	end

	for offset: number = 0, #Order - 1 do
		local id: number = Order[(start - 1 + offset) % #Order + 1]
		if Interpolate.pose(id, Pose) then
			Last = id

			return id
		end
	end

	return nil
end

-- A throw of the aim inside a cube of SPREAD either way
local function thrown(): Vector3
	return Vector3.new(
		Aim:NextNumber(-SPREAD, SPREAD),
		Aim:NextNumber(-SPREAD, SPREAD),
		Aim:NextNumber(-SPREAD, SPREAD)
	)
end

--[[
    Fires one shot into a command's shot list from the eye: aimed at the
    middle of the picked target's drawn body capsule, thrown and led, its
    look packed as the server unpacks it, and claiming the render time on
    screen. Its first segment is tested here, the rest on later frames
--]]

local function fire(client: Tread.Client, shots: { Shot }, id: number)
	local slot: Slot = Spawned[id]
	local weapon: Weapon? = WEAPONS[Firing]
	local now: number = client:getRenderTime()
	local eye: Vector3, _: Vector3 = client:getEye()

	local body: Tread.Shape = placed(slot, Pose.position).body
	local aim: Vector3 = (body.from + body.to) / 2 + thrown()
	if LEAD and weapon then
		local flight: number = (aim - eye).Magnitude / weapon.speed
		aim += Engine.toVector3(Pose.velocity) * flight
	end

	local direction: Vector3 = (aim - eye).Unit
	local yaw: number = math.round(math.atan2(-direction.X, -direction.Z) / TURN * ANGLE_STEPS) % ANGLE_STEPS
	local pitch: number = math.round(math.asin(direction.Y) / TURN * ANGLE_STEPS)
	local look: vector = Public.look(yaw * RADIANS_PER_STEP, pitch * RADIANS_PER_STEP, NO_OFFSET, NO_OFFSET, NO_OFFSET)

	local whole: number = math.floor(now)
	local fraction: number = math.floor((now - whole) * FRACTION_STEPS)

	table.insert(shots, {
		sequence = Counter % SEQUENCES,
		class = CLASS,
		renderTick = whole % RENDER_TICKS,
		fraction = fraction,
		yaw = yaw,
		pitch = pitch,
	})

	local flight: Flight = {
		counter = Counter,
		position = eye,
		direction = Engine.toVector3(look),
		weapon = weapon,
		flown = 0,
		due = whole + fraction / FRACTION_STEPS,
	}

	Counter = (Counter + 1) % COUNTER_WRAP

	if not advance(flight, now) then
		table.insert(Flights, flight)
	end
end

--[[
    Starts the shooter once a client: the shared table's rates and hit
    shapes, the drawn slots heard from then on, and the dev server's shoot.
    All three listeners live for the client session, as the exploit kit's
    do, and the frame connects only while a bullet flies or firing is on
--]]

function Shots.start(client: Tread.Client, shared: Tread.Shared)
	if Running then
		error("Shots.start runs once a client, and it has already run", 2)
	end

	Running = client
	SimulationRate = shared.rates.simulation
	RelayRate = shared.rates.relay

	local hitShapes = shared.hitShapes
	local given: { [Posture]: GameShapes } =
		{ Stand = hitShapes.Stand, Crouch = hitShapes.Crouch, Downed = hitShapes.Downed }

	for posture: Posture, shapes: GameShapes in given do
		Postures[posture] = Shapes.cross(shapes)
		Placings[posture] = Shapes.cross(shapes)

		local zones: { [string]: Tread.Shape } = {}
		for name: string, shape: Tread.Shape in shapes.zones do
			zones[name] = { from = shape.from, to = shape.to, radius = shape.radius }
		end

		Crossings[posture] =
			{ body = { from = shapes.body.from, to = shapes.body.to, radius = shapes.body.radius }, zones = zones }
	end

	client:onSpawned(function (slot: Slot, _: Model)
		Spawned[slot.id] = slot
	end)

	client:onDespawned(function (slot: Slot)
		Spawned[slot.id] = nil
	end)

	Network.shoot.on(shoot)
end

--[[
    The dev game's sample after its input's: the command's shot list
    emptied, since the input reuses it, and while firing the movement held
    at rest, so the eye a shot leaves from is the server's, the held slot
    set, and a shot every EVERY ticks at the next drawn target
--]]

function Shots.sample(command: Tread.Command)
	local fields: { [string]: any } = command.fields
	local shots: { Shot }? = fields.shots
	if shots then
		table.clear(shots)
	end

	local client: Tread.Client? = Running
	if Firing == STOP or not client then
		return
	end

	command.forward = 0
	command.right = 0
	command.jump = false
	command.crouch = false
	command.sprint = false
	command.lean = 0
	fields.slot = Firing

	Since += 1
	if Since < EVERY then
		return
	end

	local id: number? = pick()
	if id == nil then
		return
	end

	local list: { Shot } = shots or {}
	fields.shots = list
	Since = 0

	fire(client, list, id)
	hold()
end

return Shots
