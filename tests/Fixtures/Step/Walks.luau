--[[
    The trials the step's collision cases and the live scenario both run on
    the fixture geometry, each with the ending it must reach, so Lune's casts
    and the engine's answer every question alike
--]]

--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Casts = require(script.Parent.Collision)
local Collide = require(ReplicatedStorage.Packages.Tread.Step.Collide)
local Constants = require(ReplicatedStorage.Packages.Tread.Constants)
local Geometry = require(script.Parent.Geometry)
local Math = require(ReplicatedStorage.Packages.Tread.Step.Math)
local Scene = require(script.Parent.Scene)
local State = require(ReplicatedStorage.Packages.Tread.Step.State)

local SKIN: number = Constants.SKIN
local QUANTUM: number = Constants.POSITION_QUANTUM
local TOLERANCE: number = SKIN / 4 -- How far an ending may sit from where it should, well inside the skin it keeps
local FLOOR: number = Geometry.floor
local RESTING: number = FLOOR + SKIN -- Feet at rest on the floor
local RADIUS: number = Scene.settings.radius
local STANDING: number = Scene.settings.standing
local HULL: vector = vector.create(2 * RADIUS, STANDING, 2 * RADIUS) -- The standing hull's size
local EAST: vector = vector.create(10, 0, 0) -- A walk at Frontier Zero's walk speed along +X

type Collision = State.Collision
type Hit = State.Hit
type Part = Geometry.Part
type Settings = State.Settings
type State = State.State
type World = State.World

type Trial = {
	name: string,
	run: (world: World) -> string?, -- Why it ended away from where it should, or nil
}

local Walks = {}

-- Why a value ended away from where it should, or nil
local function near(label: string, got: number, want: number): string?
	if math.abs(got - want) <= TOLERANCE then
		return nil
	end

	return `{label} ended at {got}, where {want} was expected`
end

local function grounded(state: State, want: boolean): string?
	if state.grounded == want then
		return nil
	end

	return `it ended with grounded {state.grounded}, where {want} was expected`
end

local function top(part: Part): number
	return part.center.y + part.size.y / 2
end

-- The x at which the slope's face stands at height y
local function slopeAt(y: number): number
	local foot: vector = Geometry.slopeFoot
	local normal: vector = Geometry.slopeNormal

	return foot.x + (y - foot.y) * normal.y / -normal.x
end

-- The slope face's height at x
local function slopeHeight(x: number): number
	local foot: vector = Geometry.slopeFoot
	local normal: vector = Geometry.slopeNormal

	return foot.y - normal.x * (x - foot.x) / normal.y
end

-- Rounds a body's position and velocity to OwnerState's precisions, as each step ends
local function quantize(state: State)
	local at: vector = state.position
	local velocity: vector = state.velocity
	state.position = vector.create(Math.quantize(at.x), Math.quantize(at.y), Math.quantize(at.z))
	state.velocity = vector.create(
		Math.quantizeVelocity(velocity.x),
		Math.quantizeVelocity(velocity.y),
		Math.quantizeVelocity(velocity.z)
	)
end

--[[
    Steps a body for ticks, on the ground at a level velocity and in the air
    under gravity to the terminal speed, each tick quantized, and gives back
    the body its last tick ended standing on
--]]

local function walk(state: State, world: World, ground: vector, ticks: number): State?
	local settings: Settings = world.settings
	local standingOn: State? = nil

	for _ = 1, ticks do
		local velocity: vector = state.velocity
		if state.grounded then
			state.velocity = vector.create(ground.x, 0, ground.z)
		else
			local falling: number = math.max(velocity.y - settings.gravity * world.delta, -settings.terminal)
			state.velocity = vector.create(velocity.x, falling, velocity.z)
		end

		standingOn = Collide.move(state, state.velocity * world.delta, world)
		quantize(state)
	end

	return standingOn
end

-- A cast's hit checked against where it should land, or why it missed
local function landed(label: string, found: Hit?, distance: number, normal: vector): string?
	if not found then
		return `{label} hit nothing`
	end

	return near(`{label}'s distance`, found.distance, distance)
		or near(`{label}'s normal x`, found.normal.x, normal.x)
		or near(`{label}'s normal y`, found.normal.y, normal.y)
		or near(`{label}'s normal z`, found.normal.z, normal.z)
end

local TRIALS: { Trial } = {
	{
		-- A diagonal walk into the wall stops a skin short of it and slides along it the whole way
		name = "wallSlide",
		run = function (world: World): string?
			local wall: Part = Geometry.wall
			local start: vector = vector.create(15, RESTING, -22)
			local diagonal: vector = vector.create(8, 0, 5) -- Its 0.25-stud tick along Z is whole quanta, so nothing rounds away
			local ticks: number = 12

			local state: State = Scene.state(start, true)
			walk(state, world, diagonal, ticks)

			local at: vector = state.position
			local face: number = wall.center.x - wall.size.x / 2

			return near("x", at.x, face - RADIUS - SKIN)
				or near("z", at.z, start.z + diagonal.z * ticks * world.delta)
				or near("y", at.y, RESTING)
				or grounded(state, true)
		end,
	},

	{
		-- A move that would end inside a skin of the wall without reaching it still stops a skin short, so the next
		-- quantizing never puts the hull in a wall its casts would then ignore
		name = "nearMiss",
		run = function (world: World): string?
			local wall: Part = Geometry.wall
			local face: number = wall.center.x - wall.size.x / 2
			local short: number = SKIN / 4 -- Where the move alone would leave the hull's front, short of the face
			local state: State =
				Scene.state(vector.create(face - short - RADIUS - EAST.x * world.delta, RESTING, -22), true)
			walk(state, world, EAST, 1)

			return near("x", state.position.x, face - RADIUS - SKIN) or grounded(state, true)
		end,
	},

	{
		-- A walk onto the 0.5-stud step climbs it and goes on along its top
		name = "stepClimb",
		run = function (world: World): string?
			local state: State = Scene.state(vector.create(6, RESTING, -8), true)
			walk(state, world, EAST, 12)

			local at: vector = state.position

			return near("x", at.x, 12) or near("y", at.y, top(Geometry.step) + SKIN) or grounded(state, true)
		end,
	},

	{
		-- Walking off the step's far edge, the snap follows the ground down to the floor
		name = "stepDown",
		run = function (world: World): string?
			local state: State = Scene.state(vector.create(14, top(Geometry.step) + SKIN, -8), true)
			walk(state, world, EAST, 8)

			local at: vector = state.position

			return near("x", at.x, 18) or near("y", at.y, RESTING) or grounded(state, true)
		end,
	},

	{
		-- The 1-stud riser is past the step height, so the walk stops a skin short of its side
		name = "riserBlock",
		run = function (world: World): string?
			local riser: Part = Geometry.riser
			local state: State = Scene.state(vector.create(6, RESTING, 6), true)
			walk(state, world, EAST, 12)

			local at: vector = state.position
			local face: number = riser.center.x - riser.size.x / 2

			return near("x", at.x, face - RADIUS - SKIN) or near("y", at.y, RESTING) or grounded(state, true)
		end,
	},

	{
		-- The ledge's top sits under a quarter skin below a step-up's lifted hull, ground it was pressed into rather than
		-- climbed, so the step up is refused and the walk stops a skin short of its side
		name = "ledgeSliver",
		run = function (world: World): string?
			local ledge: Part = Geometry.ledge
			local state: State = Scene.state(vector.create(6, RESTING, ledge.center.z), true)
			walk(state, world, EAST, 12)

			local at: vector = state.position
			local face: number = ledge.center.x - ledge.size.x / 2

			return near("x", at.x, face - RADIUS - SKIN) or near("y", at.y, RESTING) or grounded(state, true)
		end,
	},

	{
		-- Walking off the riser's edge, a drop past the snap's reach, leaves the ground, which keeps the height it
		-- last stood at on the riser
		name = "dropOff",
		run = function (world: World): string?
			local height: number = top(Geometry.riser) + SKIN
			local state: State = Scene.state(vector.create(14, height, 6), true)
			walk(state, world, EAST, 7)

			local at: vector = state.position

			return near("x", at.x, 17.5)
				or near("y", at.y, height)
				or grounded(state, false)
				or near("the ground's height", state.groundHeight, height)
		end,
	},

	{
		-- A falling body lands on the floor through the ground probe, its fall stopped and the floor its ground's height
		name = "land",
		run = function (world: World): string?
			local state: State = Scene.state(vector.create(-20, FLOOR + 3, 20), false)
			state.velocity = vector.create(0, -10, 0)
			walk(state, world, vector.zero, 6)

			return near("y", state.position.y, RESTING)
				or near("fall", state.velocity.y, 0)
				or grounded(state, true)
				or near("the ground's height", state.groundHeight, RESTING)
		end,
	},

	{
		-- Walking into the slope, too steep to walk, gains no height and stops a skin from its face
		name = "slopeBlock",
		run = function (world: World): string?
			local state: State = Scene.state(vector.create(4, RESTING, 20), true)
			walk(state, world, EAST, 12)

			-- The hull's front bottom edge meets the face, and a level approach covers the skin over its cosine
			local at: vector = state.position
			local stop: number = slopeAt(at.y) - RADIUS - SKIN / -Geometry.slopeNormal.x

			return near("x", at.x, stop) or near("y", at.y, RESTING) or grounded(state, true)
		end,
	},

	{
		-- Landing on the slope, steep but still stood on, grounds the body with its uphill edge a skin from the face
		name = "slopeLand",
		run = function (world: World): string?
			local state: State = Scene.state(vector.create(13, FLOOR + 8, 20), false)
			walk(state, world, vector.zero, 20)

			local at: vector = state.position
			local want: number = slopeHeight(at.x + RADIUS) + SKIN / Geometry.slopeNormal.y

			return grounded(state, true) or near("y", at.y, want)
		end,
	},

	{
		-- A body sunk into the floor rises by its sinking to rest a skin above it
		name = "sunkFloor",
		run = function (world: World): string?
			local state: State = Scene.state(vector.create(-20, FLOOR - 0.3, -8), true)
			local stuck: number? = Collide.depenetrate(state, world, false)
			if stuck then
				return `it found no clear spot, sunk {stuck}`
			end

			local at: vector = state.position

			return near("y", at.y, RESTING) or near("x", at.x, -20) or near("z", at.z, -8)
		end,
	},

	{
		-- A body inside the wall leaves it level, at the first distance and way that is clear: a hull's width along +X
		name = "wallInside",
		run = function (world: World): string?
			local start: vector = vector.create(Geometry.wall.center.x, RESTING, Geometry.wall.center.z)
			local state: State = Scene.state(start, true)
			local stuck: number? = Collide.depenetrate(state, world, true)
			if stuck then
				return `it found no clear spot, sunk {stuck}`
			end

			local at: vector = state.position

			return near("x", at.x, start.x + 2 * RADIUS) or near("y", at.y, RESTING) or near("z", at.z, start.z)
		end,
	},

	{
		-- A body inside the vault, deeper than every reach, stays where it is and is reported stuck, sunk none
		name = "vaultStuck",
		run = function (world: World): string?
			local start: vector = vector.create(Geometry.vault.center.x, FLOOR + 3, Geometry.vault.center.z)
			local state: State = Scene.state(start, true)
			local stuck: number? = Collide.depenetrate(state, world, true)
			if stuck == nil then
				return "it found a clear spot inside the vault, which no reach leaves"
			elseif stuck ~= 0 then
				return `it reported sinking {stuck}, where it sank none`
			end

			local at: vector = state.position

			return near("x", at.x, start.x) or near("y", at.y, start.y) or near("z", at.z, start.z)
		end,
	},

	{
		-- Open air is clear, the wall is not, a quantum above the floor is, and a quantum into it is not
		name = "clear",
		run = function (world: World): string?
			local half: number = STANDING / 2
			local wall: vector = Geometry.wall.center

			if not Collide.clear(vector.create(-20, FLOOR + 3, 0), HULL, world) then
				return "a hull in open air was not clear"
			elseif Collide.clear(vector.create(wall.x, FLOOR + 3, wall.z), HULL, world) then
				return "a hull inside the wall was clear"
			elseif not Collide.clear(vector.create(-20, FLOOR + QUANTUM + half, 0), HULL, world) then
				return "a hull a quantum above the floor was not clear"
			elseif Collide.clear(vector.create(-20, FLOOR - QUANTUM + half, 0), HULL, world) then
				return "a hull a quantum into the floor was clear"
			end

			return nil
		end,
	},

	{
		-- The casts themselves: a ray, a box sweep, the rest height and a sphere sweep, each against a known face
		name = "casts",
		run = function (world: World): string?
			local collision: Collision = world.collision
			local half: number = STANDING / 2
			local up: vector = vector.create(0, 1, 0)
			local stepTop: number = top(Geometry.step)
			local wallFace: number = Geometry.wall.center.x - Geometry.wall.size.x / 2
			local eyeRadius: number = RADIUS - SKIN -- The eye's sphere, the hull's half width less the skin

			local rayDown: string? = landed(
				"the ray down",
				collision.ray(vector.create(-20, FLOOR + 10, 0), vector.create(0, -20, 0)),
				10,
				up
			)
			if rayDown then
				return rayDown
			end

			if collision.ray(vector.create(-20, FLOOR + 10, 0), vector.create(0, 5, 0)) then
				return "the ray up into open air hit something"
			end

			local onStep: Hit? = collision.sweep(vector.create(13, FLOOR + 4, -8), HULL, vector.create(0, -10, 0))
			local stepSweep: string? = landed("the sweep onto the step", onStep, FLOOR + 4 - half - stepTop, up)
			if stepSweep then
				return stepSweep
			end

			local toSlope: Hit? = collision.sweep(vector.create(4, RESTING + half, 20), HULL, EAST)
			local slopeSweep: string? =
				landed("the sweep into the slope", toSlope, slopeAt(RESTING) - RADIUS - 4, Geometry.slopeNormal)
			if slopeSweep then
				return slopeSweep
			end

			local rest: number? = collision.rest(vector.create(9, FLOOR + 3, -8), HULL)
			if not rest then
				return "the rest height over the step's edge found nothing"
			end

			local restAt: string? = near("the rest height over the step's edge", rest, stepTop)
			if restAt then
				return restAt
			end

			local toWall: Hit? = collision.sphere(vector.create(15, FLOOR + 4, -22), eyeRadius, EAST)

			return landed("the sphere into the wall", toWall, wallFace - 15 - eyeRadius, vector.create(-1, 0, 0))
		end,
	},

	{
		-- Another body's hull stops a walk a skin short of it
		name = "hullStop",
		run = function (world: World): string?
			local other: State = Scene.state(vector.create(-20, RESTING, 0), true)
			local state: State = Scene.state(vector.create(-26, RESTING, 0), true)
			world.bodies = { other, state }
			walk(state, world, EAST, 10)

			local at: vector = state.position

			return near("x", at.x, other.position.x - 2 * RADIUS - SKIN) or near("y", at.y, RESTING)
		end,
	},

	{
		-- A body falling onto another's head lands on its hull top and stands on it
		name = "headLand",
		run = function (world: World): string?
			local other: State = Scene.state(vector.create(-20, RESTING, 0), true)
			local state: State = Scene.state(vector.create(-20, RESTING + STANDING + 1, 0), false)
			world.bodies = { other, state }

			local standingOn: State? = walk(state, world, vector.zero, 10)
			if standingOn ~= other then
				return "it ended standing on no body's hull, where the other's was expected"
			end

			return near("y", state.position.y, RESTING + STANDING + SKIN) or grounded(state, true)
		end,
	},

	{
		-- A downed body blocks no one, so a walk passes through its hull
		name = "downedPass",
		run = function (world: World): string?
			local other: State = Scene.state(vector.create(-20, RESTING, 0), true)
			other.posture = "Downed"
			local state: State = Scene.state(vector.create(-26, RESTING, 0), true)
			world.bodies = { other, state }
			walk(state, world, EAST, 16)

			return near("x", state.position.x, -18) or near("y", state.position.y, RESTING)
		end,
	},
}

-- Every trial's name, in the order the live scenario runs them
Walks.names = {} :: { string }

for _, trial: Trial in TRIALS do
	table.insert(Walks.names, trial.name)
end

--[[
    Runs one trial by name over a collision, Lune's fixture casts over the
    fixture geometry when none is given, and gives whether it ended where it
    should, with the reason when it did not
--]]

function Walks.run(name: string, collision: Collision?): (boolean, string | nil)
	for _, trial: Trial in TRIALS do
		if trial.name == name then
			local failure: string? = trial.run(Scene.world(collision or Casts(Geometry.parts)))
			if failure then
				return false, `{name}: {failure}`
			end

			return true, nil
		end
	end

	return false, `no trial is named {name}`
end

return Walks
