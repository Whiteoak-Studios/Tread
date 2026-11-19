--[[
    The crouch slide: whether Tread's own physics lets one start, its start
    at the body's speed and boost, and a tick's slope, friction, steering,
    cap and walk, with the ends the move gives and the cooldown after them
--]]

--!strict
--!native
local Collide = require(script.Parent.Collide)
local Math = require(script.Parent.Math)
local State = require(script.Parent.State)

local DEGREES: number = math.pi / 180 -- Radians a degree, which the game's steer is given in

type Settings = State.Settings
type SlideSettings = State.Slide
type State = State.State
type World = State.World

local Slide = {}

-- The game's slide settings, which only a step block that gives them lets a slide reach
local function settingsOf(settings: Settings): SlideSettings
	local slide: SlideSettings? = settings.slide
	if not slide then
		error("A crouch slide ran on a step block that gives no slide")
	end

	return slide
end

-- The horizontal speed a body carries
local function speedOf(state: State): number
	local velocity: vector = state.velocity

	return math.sqrt(velocity.x * velocity.x + velocity.z * velocity.z)
end

--[[
    Whether Tread's own physics lets a slide start this tick, before the
    game's rules and the input: a step block that gives one, a walking body
    on walkable ground, not downed, its cooldown run out, and the
    horizontal speed it carried into the tick at least the slide's start
--]]

function Slide.allows(state: State, world: World): boolean
	local settings: Settings = world.settings
	local slide: SlideSettings? = settings.slide
	if not slide or state.mode ~= "Ground" or not state.grounded or state.posture == "Downed" then
		return false
	elseif state.slideCooldown > 0 or state.groundNormal.y < settings.walkable then
		return false
	end

	return speedOf(state) >= slide.start
end

--[[
    Starts a slide in the body's horizontal direction, at its speed plus
    the boost but never past the greater of its speed and the sprint plus
    the boost, so a body already faster than that gains nothing
--]]

function Slide.start(state: State, settings: Settings)
	local slide: SlideSettings = settingsOf(settings)
	local velocity: vector = state.velocity
	local speed: number = speedOf(state)
	local boosted: number = math.min(speed + slide.boost, math.max(speed, settings.sprint + slide.boost))
	local share: number = boosted / speed

	state.velocity = vector.create(velocity.x * share, 0, velocity.z * share)
	state.mode = "Slide"
end

--[[
    The horizontal velocity a jump out of a slide leaves with, held to the
    slide's top speed
--]]

function Slide.held(state: State, settings: Settings): (number, number)
	local most: number = settingsOf(settings).max
	local velocity: vector = state.velocity
	local speed: number = speedOf(state)
	if speed <= most then
		return velocity.x, velocity.z
	end

	local share: number = most / speed

	return velocity.x * share, velocity.z * share
end

--[[
    One tick of a slide past its jump and its letting go, in order: the
    slope's share of gravity along the ground, the friction, the turn
    toward the move input at most the game's steer, the top speed, then
    the walk's own move. It ends in the air when the move leaves the ground,
    and crouched on the ground on footing too steep to walk or below its
    stop speed. Gives back the body whose hull top it ends standing on

    @ steerX | the move input's direction on the ground, any length, zero for none
    @ gravity | the gravity the world gives the tick, studs/s²
--]]

function Slide.run(state: State, world: World, steerX: number, steerZ: number, gravity: number): State?
	local settings: Settings = world.settings
	local slide: SlideSettings = settingsOf(settings)
	local delta: number = world.delta
	local velocity: vector = state.velocity
	local normal: vector = state.groundNormal

	-- 1) Gravity's share along the ground, which points downhill
	local push: number = slide.slope * gravity * normal.y * delta
	local vx: number = velocity.x + push * normal.x
	local vz: number = velocity.z + push * normal.z

	-- 2) Friction off its speed, keeping its direction
	local speed: number = math.sqrt(vx * vx + vz * vz)
	local aheadX: number, aheadZ: number = 0, 0
	if speed > 0 then
		aheadX, aheadZ = vx / speed, vz / speed
	end

	speed = math.max(speed - slide.friction * delta, 0)

	-- 3) The turn toward the input, the input's own direction once it lies within this tick's turn
	local wanted: number = math.sqrt(steerX * steerX + steerZ * steerZ)
	if speed > 0 and wanted > 0 then
		local towardX: number, towardZ: number = steerX / wanted, steerZ / wanted
		local most: number = slide.steer * DEGREES * delta
		local cosine: number = Math.cos(most)

		if aheadX * towardX + aheadZ * towardZ >= cosine then
			aheadX, aheadZ = towardX, towardZ
		else
			-- The side the input lies on, from the cross of the two directions, a turn either way when directly behind
			local sine: number = Math.sin(most)
			if aheadX * towardZ - aheadZ * towardX < 0 then
				sine = -sine
			end

			aheadX, aheadZ = aheadX * cosine - aheadZ * sine, aheadX * sine + aheadZ * cosine
		end
	end

	-- 4) The top speed, which no downhill passes
	speed = math.min(speed, slide.max)

	-- 5) The walk's collide-and-slide, step up and ground snap, so a wall takes its speed as it takes a walk's
	state.velocity = vector.create(aheadX * speed, 0, aheadZ * speed)
	local below: State? = Collide.move(state, vector.create(aheadX * speed * delta, 0, aheadZ * speed * delta), world)

	if not state.grounded then
		state.mode = "Air"
	elseif state.groundNormal.y < settings.walkable or speedOf(state) < slide.stop then
		state.mode = "Ground"
	end

	return below
end

--[[
    Starts the cooldown a slide's end leaves, in whole ticks of the world,
    which every end but leaving the ground takes
--]]

function Slide.finish(state: State, world: World)
	local slide: SlideSettings? = world.settings.slide
	if slide then
		state.slideCooldown = math.round(slide.cooldown / world.delta)
	end
end

return Slide
