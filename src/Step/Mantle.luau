--[[
    The mantle: a jump press facing a ledge in reach finds it with the hull's
    sweeps, then a fixed path rises beside the face and arches over onto its
    top over the game's mantle time, swept each tick it moves
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
local CLEARS_AT: number = 0.5 -- How far into its tick the feet reach the rise, so that tick turns half the corner
local AIR: Enum.Material = Enum.Material.Air

type Collision = State.Collision
type Command = State.Command
type Hit = State.Hit
type Mode = State.Mode
type Posture = State.Posture
type Settings = State.Settings
type State = State.State
type World = State.World

local Mantle = {}

-- How far the path goes ahead from the face: the hull's width and a skin either side, so it ends a skin past the face
local function overOf(settings: Settings): number
	return settings.radius + settings.radius + SKIN + SKIN
end

--[[
    Whether a hull of size has room for the path from feet at x, y, z: up
    beside the face by the rise and the arc, ahead by the path's move at
    every height from the rise to the arc over it, each with a skin past
    it, and space with a skin over its top where the path ends
--]]

local function room(
	world: World,
	size: vector,
	x: number,
	y: number,
	z: number,
	rise: number,
	arc: number,
	ahead: vector
): boolean
	local collision: Collision = world.collision
	local half: number = size.y / 2

	-- To the arc's height, so the tall sweep ahead never starts inside a part it would then skip
	if collision.sweep(vector.create(x, y + half, z), size, vector.create(0, rise + arc + SKIN, 0)) then
		return false
	end

	-- One box the hull's height and the arc's together covers the hull at every height the path goes ahead at
	local tall: vector = vector.create(size.x, size.y + arc, size.z)
	local length: number = math.sqrt(ahead.x * ahead.x + ahead.z * ahead.z)
	local reach: vector = ahead * ((length + SKIN) / length)
	if collision.sweep(vector.create(x, y + rise + tall.y / 2, z), tall, reach) then
		return false
	end

	local spaced: vector = vector.create(size.x, size.y + SKIN, size.z)
	local ending: vector = vector.create(x + ahead.x, y + rise + spaced.y / 2, z + ahead.z)

	return Collide.clear(ending, spaced, world)
end

--[[
    The ledge a jump press would mantle onto from where the body is, found
    as a press finds it and changing nothing: a walking body, not downed,
    on the ground, in the air or swimming, facing a face too steep to walk
    within its hull's radius ahead with no body nearer, whose own top rises
    past a step, a walkable top past it over a step and within the game's
    reach of the ground last stood on, or of a swimmer's feet, and room for
    the path. Gives back the posture it would end in, nil for none, then the
    feet's x and z at the face, where the path starts, and its rise
--]]

function Mantle.find(state: State, world: World): (Posture?, number, number, number)
	local mode: Mode = state.mode
	if state.moveMode ~= "Walk" or state.posture == "Downed" then
		return nil, 0, 0, 0
	elseif mode ~= "Ground" and mode ~= "Air" and mode ~= "Swim" then
		return nil, 0, 0, 0
	end

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
		return nil, 0, 0, 0
	end

	-- Read before the next cast reuses the hit
	local normal: vector = face.normal
	local distance: number = face.distance
	local facing: number = -(aheadX * normal.x + aheadZ * normal.z)
	if facing <= 0 or normal.y >= settings.walkable then
		return nil, 0, 0, 0
	end

	local travel: number = math.max(distance - SKIN / facing, 0)
	local bodies: number, _: vector, _: State? = Hulls.sweep(state, center, size, toward, world)
	if bodies <= distance then
		return nil, 0, 0, 0
	end

	-- 2) The face's own top, swept down from above the reach a skin into the face, to a step's height over the feet
	local base: number = state.groundHeight
	if mode == "Swim" then
		base = feet.y
	end

	local reach: number = base + settings.mantleHeight
	local lowest: number = feet.y + settings.stepHeight
	if reach <= lowest then
		return nil, 0, 0, 0
	end

	-- A plate the hull's footprint and a skin thick, swept down from over the reach to a step over the feet
	local probeSize: vector = vector.create(width, SKIN, width)
	local probeBottom: number = reach + SKIN
	local down: vector = vector.create(0, lowest - probeBottom, 0)

	-- Where the hull met the face, sunk a skin into it along its normal at any angle of approach, so it finds that
	-- face's top and never the next one's. A face no higher than a step there is a riser or a curb the walk climbs,
	-- however high stairs rise past it, and the sweep skips one past the reach there, which starts the plate inside it
	local sunk: vector = vector.create(
		feet.x + aheadX * distance - normal.x * SKIN,
		probeBottom + SKIN / 2,
		feet.z + aheadZ * distance - normal.z * SKIN
	)
	local own: Hit? = collision.sweep(sunk, probeSize, down)
	if not own or Math.quantize(probeBottom - own.distance) <= lowest then
		return nil, 0, 0, 0
	end

	-- 3) The top past the face, where the path ends, on the position quanta so every tick from here lands on them
	local x: number = Math.quantize(feet.x + aheadX * travel)
	local z: number = Math.quantize(feet.z + aheadZ * travel)
	local over: number = overOf(settings)
	local ahead: vector = vector.create(aheadX * over, 0, aheadZ * over)

	-- The same plate, which finds the ledge rising past the reach as no clear spot
	local probe: vector = vector.create(x + ahead.x, probeBottom + SKIN / 2, z + ahead.z)
	if not Collide.clear(probe, probeSize, world) then
		return nil, 0, 0, 0
	end

	local found: Hit? = collision.sweep(probe, probeSize, down)
	if not found or found.normal.y < settings.walkable then
		return nil, 0, 0, 0
	end

	-- On the position quanta, so a top at the reach is in it on every realm
	local top: number = Math.quantize(probeBottom - found.distance)
	if top - base > settings.mantleHeight or top <= lowest then
		return nil, 0, 0, 0
	end

	-- 4) The rise to a skin over the top, rounded up to the step the state carries it in
	local rise: number = math.ceil((top + SKIN - feet.y) / RISE_QUANTUM) * RISE_QUANTUM
	if rise > RISE_LIMIT then
		return nil, 0, 0, 0
	end

	-- 5) The posture it ends in
	local arc: number = settings.mantleArc
	local standing: vector = vector.create(width, settings.standing, width)
	local crouched: vector = vector.create(width, settings.crouched, width)
	if state.posture ~= "Crouch" and room(world, standing, x, feet.y, z, rise, arc, ahead) then
		return "Stand", x, z, rise
	elseif room(world, crouched, x, feet.y, z, rise, arc, ahead) then
		return "Crouch", x, z, rise
	end

	return nil, 0, 0, 0
end

--[[
    Starts a mantle on a jump press where find gives one: the body moves to
    the face, at rest, in the posture it will end in. Does nothing otherwise
--]]

function Mantle.start(state: State, world: World)
	local posture: Posture?, x: number, z: number, rise: number = Mantle.find(state, world)
	if not posture then
		return
	end

	state.position = vector.create(x, state.position.y, z)
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
    Where a jump press now would end the feet, on the path's last tick
    before the walk's ground snap stands them on the top, or nil when no
    press would start a mantle. Changes nothing on the body
--]]

function Mantle.ending(state: State, world: World): vector?
	local posture: Posture?, x: number, z: number, rise: number = Mantle.find(state, world)
	if not posture then
		return nil
	end

	local over: number = overOf(world.settings)
	local aheadX: number = Math.quantize(-Math.sin(state.facing) * over)
	local aheadZ: number = Math.quantize(-Math.cos(state.facing) * over)

	return vector.create(x + aheadX, state.position.y + rise, z + aheadZ)
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
    The feet's place on the path after done of its ticks, ahead along the
    facing and up from where it started. They rise at one pace until
    halfway through the tick that clears the rise, the rise's share of the
    path in whole ticks, keeping one before the last. Then they go ahead at
    one pace while a parabola either side lifts them to the arc over the
    rise on the tick nearest the middle of the rest, and down onto it again
--]]

local function place(done: number, ticks: number, rise: number, arc: number, over: number): (number, number)
	if done >= ticks then
		return over, rise
	end

	local rising: number = math.max(math.min(math.floor(rise / (rise + over) * ticks), ticks - 2), 0)
	local clears: number = rising + CLEARS_AT
	if done <= rising then
		return 0, rise * done / clears
	end

	local peak: number = math.clamp(math.round((clears + ticks) / 2), rising + 1, ticks - 1)
	local side: number -- How far from the peak toward the end of the arch it is on, 0 to 1
	if done <= peak then
		side = (peak - done) / (peak - clears)
	else
		side = (done - peak) / (ticks - peak)
	end

	return over * (done - clears) / (ticks - clears), rise + arc * (1 - side * side)
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
    One tick of the path, over the game's mantle time, along the facing it
    holds. Each tick's place is on the position quanta from the start, so
    its replay lands on the same numbers. The tick's climb below the rise
    goes first, so the path never cuts the ledge's edge, then its move
    ahead, then what the arch lifts or lowers it by. A block drops it into
    the air where it stopped, going down cancels it, and its last tick
    stands it on the top through the walk's ground snap
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
	local arc: number = settings.mantleArc
	local over: number = overOf(settings)
	local aheadX: number = -Math.sin(state.facing)
	local aheadZ: number = -Math.cos(state.facing)

	local fromAhead: number, fromUp: number = place(done - 1, ticks, rise, arc, over)
	local toAhead: number, toUp: number = place(done, ticks, rise, arc, over)
	local x: number = Math.quantize(aheadX * toAhead) - Math.quantize(aheadX * fromAhead)
	local z: number = Math.quantize(aheadZ * toAhead) - Math.quantize(aheadZ * fromAhead)
	local fromY: number = Math.quantize(fromUp)
	local toY: number = Math.quantize(toUp)
	local climb: number = math.max(math.min(toY, rise) - fromY, 0)

	if
		not sweep(state, world, 0, climb, 0)
		or not sweep(state, world, x, 0, z)
		or not sweep(state, world, 0, toY - fromY - climb, 0)
	then
		Mantle.cancel(state)

		return
	end

	state.velocity = vector.create(x / delta, (toY - fromY) / delta, z / delta)
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
