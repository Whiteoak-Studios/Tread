--[[
    The cleared eye both realms read for the camera, a shot, reach, line of
    sight and anti-ESP: the eased eye moved by the lean, then held the
    game's clearance from every wall and ceiling
--]]

--!strict
--!native
local Constants = require(script.Parent.Parent.Constants)
local Hulls = require(script.Parent.Hulls)
local Math = require(script.Parent.Math)
local State = require(script.Parent.State)

local SKIN: number = Constants.SKIN

type Collision = State.Collision
type Hit = State.Hit
type Settings = State.Settings
type State = State.State
type World = State.World

local Eye = {}

-- How far a level ray along one world axis found a wall, the clearance when it found none
local function reach(collision: Collision, origin: vector, direction: vector, clearance: number): number
	local found: Hit? = collision.ray(origin, direction)
	if found then
		return found.distance
	end

	return clearance
end

--[[
    How far the rays along one world axis push the eye, toward the farther
    of two walls nearer than the clearance until it sits midway, else away
    from the one wall nearer than that

    @ ahead | the distance along the axis, behind the one against it
--]]

local function push(ahead: number, behind: number, clearance: number): number
	if ahead < clearance and behind < clearance then
		return (ahead - behind) / 2
	elseif ahead < clearance then
		return ahead - clearance
	elseif behind < clearance then
		return clearance - behind
	end

	return 0
end

--[[
    The cleared eye: the feet plus the eased eye height, moved by the lean's
    share of the game's eye shift, which a sphere a skin inside the hull then
    holds the clearance below any ceiling over the hull's axis and short of
    any wall toward the lean, and four level rays push away from any wall
    nearer than the clearance. Six queries, which allocate nothing
--]]

function Eye.clear(state: State, world: World): vector
	local settings: Settings = world.settings
	local collision: Collision = world.collision
	local clearance: number = settings.clearance
	local radius: number = settings.radius - SKIN
	local feet: vector = state.position

	-- 1) The wanted eye: sideways by the lean's share of the shift, and down and back by the share's size
	local share: number = 0
	if settings.lean > 0 then
		share = state.lean / settings.lean
	end

	local shift: vector = world.leanShift
	local amount: number = math.abs(share)
	local sideways: number = Math.lerp(0, shift.x, share)
	local down: number = Math.lerp(0, shift.y, amount)
	local back: number = Math.lerp(0, shift.z, amount)
	local sine: number = Math.sin(state.facing)
	local cosine: number = Math.cos(state.facing)
	local shiftX: number = cosine * sideways + sine * back
	local shiftZ: number = cosine * back - sine * sideways

	local wanted: number = feet.y + state.eyeHeight + down
	local start: number = feet.y + Hulls.height(state, settings) - settings.clearanceStart
	local x: number, y: number, z: number = feet.x, wanted, feet.z

	-- 2) Up the hull's axis from below its top, the eye held the clearance under a ceiling the sphere meets
	local rise: number = wanted - start
	if rise > 0 then
		local found: Hit? = collision.sphere(vector.create(x, start, z), radius, vector.create(0, rise, 0))
		if found then
			y = math.min(wanted, start + found.distance + radius - clearance)
		end
	end

	-- 3) Level toward the lean, stopping the clearance short of a wall the sphere meets
	local lean: number = math.sqrt(shiftX * shiftX + shiftZ * shiftZ)
	if lean > 0 then
		local travel: number = lean
		local found: Hit? = collision.sphere(vector.create(x, y, z), radius, vector.create(shiftX, 0, shiftZ))
		if found then
			travel = math.clamp(found.distance + radius - clearance, 0, lean)
		end

		x += shiftX / lean * travel
		z += shiftZ / lean * travel
	end

	-- 4) Away from any wall nearer than the clearance along the world's axes, from one point
	local at: vector = vector.create(x, y, z)
	local east: number = reach(collision, at, vector.create(clearance, 0, 0), clearance)
	local west: number = reach(collision, at, vector.create(-clearance, 0, 0), clearance)
	local south: number = reach(collision, at, vector.create(0, 0, clearance), clearance)
	local north: number = reach(collision, at, vector.create(0, 0, -clearance), clearance)

	return vector.create(x + push(east, west, clearance), y, z + push(south, north, clearance))
end

return Eye
