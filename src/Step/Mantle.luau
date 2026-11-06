--[[
    The mantle: a jump press facing a ledge in reach finds it with the hull's
    sweeps, then a fixed path runs straight up and forward onto its top
    over the game's mantle time, swept each tick it moves
--]]

--!strict
--!native
local Collide = require(script.Parent.Collide)
local Constants = require(script.Parent.Parent.Constants)
local Hulls = require(script.Parent.Hulls)
local Math = require(script.Parent.Math)
local State = require(script.Parent.State)

local SKIN: number = Constants.SKIN
local RISE_QUANTUM: number = Constants.EYE_QUANTUM -- The step the state's mantle rise rides in
local RISE_LIMIT: number = (2 ^ Constants.EYE_BITS - 1) * RISE_QUANTUM -- The highest rise that u8 holds
local MIN_MOVE: number = Constants.POSITION_QUANTUM -- A path tick shorter than one quantum moves without a sweep
local AIR: Enum.Material = Enum.Material.Air

type Collision = State.Collision
type Command = State.Command
type Hit = State.Hit
type Posture = State.Posture
type Settings = State.Settings
type State = State.State
type World = State.World

local Mantle = {}

--[[
    Whether a hull of size has room for the path from feet at x, y, z: up
    by the rise beside the face and then ahead by the path's move at the
    top's height, each with a skin past it, and space with a skin over its
    top where the path ends
--]]

local function room(world: World, size: vector, x: number, y: number, z: number, rise: number, ahead: vector): boolean
	local collision: Collision = world.collision
	local half: number = size.y / 2

	if collision.sweep(vector.create(x, y + half, z), size, vector.create(0, rise + SKIN, 0)) then
		return false
	end

	local length: number = math.sqrt(ahead.x * ahead.x + ahead.z * ahead.z)
	local reach: vector = ahead * ((length + SKIN) / length)
	if collision.sweep(vector.create(x, y + rise + half, z), size, reach) then
		return false
	end

	local spaced: vector = vector.create(size.x, size.y + SKIN, size.z)
	local ending: vector = vector.create(x + ahead.x, y + rise + spaced.y / 2, z + ahead.z)

	return Collide.clear(ending, spaced, world)
end

--[[
    Starts a mantle on a jump press when the body faces a ledge: a face
    too steep to walk within its hull's radius ahead, a walkable top past
    it no higher than the game's reach above the ground it last stood on,
    or above its feet for a swimmer, and higher than a step, and room for
    the path. It ends standing where the standing hull fits, or crouched,
    and crouched for a body crouched now. Does nothing otherwise
--]]

function Mantle.start(state: State, world: World)
	local settings: Settings = world.settings
	local collision: Collision = world.collision
	local radius: number = settings.radius
	local width: number = radius + radius
	local feet: vector = state.position
	local aheadX: number = -Math.sin(state.facing)
	local aheadZ: number = -Math.cos(state.facing)

	-- 1) The face, nearer than any other body
	local height: number = Hulls.height(state, settings)
	local center: vector = vector.create(feet.x, feet.y + height / 2, feet.z)
	local size: vector = vector.create(width, height, width)
	local toward: vector = vector.create(aheadX * radius, 0, aheadZ * radius)
	local face: Hit? = collision.sweep(center, size, toward)
	if not face then
		return
	end

	-- Read before the next cast reuses the hit
	local normal: vector = face.normal
	local distance: number = face.distance
	local facing: number = -(aheadX * normal.x + aheadZ * normal.z)
	if facing <= 0 or normal.y >= settings.walkable then
		return
	end

	local travel: number = math.max(distance - SKIN / facing, 0)
	local bodies: number, _: vector, _: State? = Hulls.sweep(state, center, size, toward, world)
	if bodies <= distance then
		return
	end

	-- 2) The top, swept down from above the reach just past the face, to a step's height over the feet
	local base: number = state.groundHeight
	if state.mode == "Swim" then
		base = feet.y
	end

	local reach: number = base + settings.mantleHeight
	local lowest: number = feet.y + settings.stepHeight
	if reach <= lowest then
		return
	end

	local x: number = feet.x + aheadX * travel
	local z: number = feet.z + aheadZ * travel
	local over: number = width + SKIN + SKIN -- Past the face by a skin
	local ahead: vector = vector.create(aheadX * over, 0, aheadZ * over)

	-- A plate the hull's footprint and a skin thick, which finds the ledge rising past the reach as no clear spot
	local probeSize: vector = vector.create(width, SKIN, width)
	local probeBottom: number = reach + SKIN
	local probe: vector = vector.create(x + ahead.x, probeBottom + SKIN / 2, z + ahead.z)
	if not Collide.clear(probe, probeSize, world) then
		return
	end

	local found: Hit? = collision.sweep(probe, probeSize, vector.create(0, lowest - probeBottom, 0))
	if not found or found.normal.y < settings.walkable then
		return
	end

	-- On the position quanta, so a top at the reach is in it on every realm
	local top: number = Math.quantize(probeBottom - found.distance)
	if top - base > settings.mantleHeight or top <= lowest then
		return
	end

	-- 3) The rise to a skin over the top, rounded up to the step the state carries it in
	local rise: number = math.ceil((top + SKIN - feet.y) / RISE_QUANTUM) * RISE_QUANTUM
	if rise > RISE_LIMIT then
		return
	end

	-- 4) The posture it ends in
	local posture: Posture
	local standing: vector = vector.create(width, settings.standing, width)
	local crouched: vector = vector.create(width, settings.crouched, width)
	if state.posture ~= "Crouch" and room(world, standing, x, feet.y, z, rise, ahead) then
		posture = "Stand"
	elseif room(world, crouched, x, feet.y, z, rise, ahead) then
		posture = "Crouch"
	else
		return
	end

	state.position = vector.create(x, feet.y, z)
	state.velocity = vector.zero
	state.mode = "Mantle"
	state.posture = posture
	state.grounded = false
	state.groundNormal = vector.zero
	state.groundMaterial = AIR
	state.mantleTicks = 0
	state.mantleRise = rise
end

--[[
    Ends a mantle where the body stands, dropping it into the air from
    rest, as going down, a block on its path or a move mode change does
--]]

function Mantle.cancel(state: State)
	state.mode = "Air"
	state.velocity = vector.zero
	state.mantleTicks = 0
	state.mantleRise = 0
end

--[[
    Moves the body by one tick of its path, swept against the world and
    the other live hulls with a skin past the move. Gives back whether it
    went the whole way, and when it did not, leaves it a skin short of
    what it met
--]]

local function sweep(state: State, world: World, x: number, y: number, z: number): boolean
	local feet: vector = state.position
	local length: number = math.sqrt(x * x + y * y + z * z)
	if length < MIN_MOVE then
		state.position = vector.create(feet.x + x, feet.y + y, feet.z + z)

		return true
	end

	local settings: Settings = world.settings
	local height: number = Hulls.height(state, settings)
	local width: number = settings.radius + settings.radius
	local center: vector = vector.create(feet.x, feet.y + height / 2, feet.z)
	local size: vector = vector.create(width, height, width)
	local stretch: number = (length + SKIN) / length
	local direction: vector = vector.create(x * stretch, y * stretch, z * stretch)

	local nearest: number, _: vector, _: State? = Hulls.sweep(state, center, size, direction, world)
	local found: Hit? = world.collision.sweep(center, size, direction)
	if found then
		nearest = math.min(nearest, found.distance)
	end

	local travel: number = math.max(nearest - SKIN, 0)
	if travel >= length then
		state.position = vector.create(feet.x + x, feet.y + y, feet.z + z)

		return true
	end

	local share: number = travel / length
	state.position = vector.create(feet.x + x * share, feet.y + y * share, feet.z + z * share)

	return false
end

--[[
    One tick of the path, which runs from where it started at one pace
    over the game's mantle time: up by the rise, then ahead past the face
    along the facing it holds. Each tick's place is on the position quanta
    from the start, so its replay lands on the same numbers. A block drops
    it into the air where it stopped, going down cancels it, and its last
    tick stands it on the top through the walk's ground snap
--]]

function Mantle.run(state: State, _: Command, world: World)
	if state.posture == "Downed" then
		Mantle.cancel(state)

		return
	end

	local settings: Settings = world.settings
	local delta: number = world.delta
	local ticks: number = math.round(settings.mantleTime / delta) -- From 1 to 255, which Config holds the game's time to
	local done: number = state.mantleTicks + 1
	local rise: number = state.mantleRise
	local over: number = settings.radius + settings.radius + SKIN + SKIN
	local length: number = rise + over
	local from: number = (done - 1) / ticks * length
	local to: number = done / ticks * length
	local aheadX: number = -Math.sin(state.facing)
	local aheadZ: number = -Math.cos(state.facing)

	local fromAhead: number = math.max(from - rise, 0)
	local toAhead: number = math.max(to - rise, 0)
	local x: number = Math.quantize(aheadX * toAhead) - Math.quantize(aheadX * fromAhead)
	local y: number = Math.quantize(math.min(to, rise)) - Math.quantize(math.min(from, rise))
	local z: number = Math.quantize(aheadZ * toAhead) - Math.quantize(aheadZ * fromAhead)

	-- The tick that tops the rise rises first and then goes ahead, so the path never cuts the ledge's edge
	if not sweep(state, world, 0, y, 0) or not sweep(state, world, x, 0, z) then
		Mantle.cancel(state)

		return
	end

	state.velocity = vector.create(x / delta, y / delta, z / delta)
	state.mantleTicks = done
	if done < ticks then
		return
	end

	state.velocity = vector.zero
	state.mantleTicks = 0
	state.mantleRise = 0
	state.grounded = true
	Collide.move(state, vector.zero, world)

	if state.grounded then
		state.mode = "Ground"
	else
		state.mode = "Air"
	end
end

return Mantle
