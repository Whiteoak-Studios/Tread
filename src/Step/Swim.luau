--[[
    Swimming: the water's surface and depth at a body, the water level its
    state word carries, and a swimmer's tick, steered along its look and
    floating at the game's float depth when it gives no input
--]]

--!strict
--!native
local Collide = require(script.Parent.Collide)
local Math = require(script.Parent.Math)
local State = require(script.Parent.State)

type Command = State.Command
type Settings = State.Settings
type State = State.State
type WaterLevel = State.WaterLevel
type World = State.World

local Swim = {}

--[[
    The height of the water's surface over a body's feet, from the game's
    water query, nil where there is none or the game gives none
--]]

function Swim.surface(state: State, world: World): number?
	local water = world.water
	if not water then
		return nil
	end

	local feet: vector = state.position
	local height: number? = water(feet.x, feet.z)
	if height == nil then
		return nil
	end

	-- A value less itself is 0 only when the value is a finite number
	if type(height) ~= "number" or height - height ~= 0 then
		error(`The water query must give a finite height or nil, and got {height}`)
	end

	return height
end

--[[
    The water's depth where a body stands: the surface less the ground
    under its feet, found as far down as the walk's ground snap reaches,
    and deep past any depth where that finds no ground
--]]

function Swim.depth(state: State, world: World, surface: number): number
	local settings: Settings = world.settings
	local reach: number = settings.stepHeight -- The rest query looks two skins further, the snap's whole reach
	local width: number = settings.radius + settings.radius
	local feet: vector = state.position

	local ground: number? =
		world.collision.rest(vector.create(feet.x, feet.y - reach / 2, feet.z), vector.create(width, reach, width))
	if not ground then
		return math.huge
	end

	return surface - ground
end

--[[
    The water level a body's state word carries: dry with its feet out of
    the water, head under while its eye is below the surface, and above
    that a surface swim for a swimmer and wading for anyone else
--]]

function Swim.level(state: State, surface: number?): WaterLevel
	local feet: number = state.position.y
	if not surface or surface <= feet then
		return "Dry"
	elseif feet + state.eyeHeight < surface then
		return "Under"
	elseif state.mode == "Swim" then
		return "Surface"
	end

	return "Wading"
end

--[[
    A swimmer's tick: its velocity eased toward the move along its whole
    look at the game's water ease, with no gravity. Given no input it eases
    toward the float depth instead, no faster than the swim speed, and
    rising, by input or by floating, stops at the float depth

    @ surface | the water's surface where the tick started, nil for none
    @ speed | the tick's swim speed, under the rules' cap
--]]

function Swim.run(
	state: State,
	command: Command,
	world: World,
	surface: number?,
	forward: number,
	right: number,
	speed: number
)
	local settings: Settings = world.settings
	local delta: number = world.delta
	local sine: number = Math.sin(state.facing)
	local cosine: number = Math.cos(state.facing)
	local ahead: number = forward * Math.cos(command.pitch)

	local targetX: number = (right * cosine - ahead * sine) * speed
	local targetY: number = forward * Math.sin(command.pitch) * speed
	local targetZ: number = -(right * sine + ahead * cosine) * speed
	local feet: vector = state.position

	local float: number? = nil
	if surface then
		float = surface - settings.floatDepth
	end

	if float and forward == 0 and right == 0 then
		local most: number = settings.swim
		targetY = math.clamp((float - feet.y) * settings.waterEase, -most, most)
	end

	local ease: number = math.min(settings.waterEase * delta, 1)
	local velocity: vector = state.velocity
	local vx: number = Math.lerp(velocity.x, targetX, ease)
	local vy: number = Math.lerp(velocity.y, targetY, ease)
	local vz: number = Math.lerp(velocity.z, targetZ, ease)
	local rise: number = vy * delta

	if float and rise > 0 and feet.y + rise > float then
		rise = math.max(float - feet.y, 0)
		vy = 0
	end

	state.velocity = vector.create(vx, vy, vz)
	state.grounded = false
	Collide.move(state, vector.create(vx * delta, rise, vz * delta), world)
end

return Swim
