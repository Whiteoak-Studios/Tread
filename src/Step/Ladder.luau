--[[
    Ladders: which registered ladder a body touches, mounting one by walking
    into it while facing it, and a climber's tick with its jump off, its
    step off at the top and its stand at the foot
--]]

--!strict
--!native
local Collide = require(script.Parent.Collide)
local Hulls = require(script.Parent.Hulls)
local Math = require(script.Parent.Math)
local State = require(script.Parent.State)

local DEGREES: number = math.pi / 180 -- Radians a degree, which the game's ladder drop is given in

type Box = State.Box
type Command = State.Command
type Ladder = State.Ladder
type Settings = State.Settings
type State = State.State
type World = State.World

local Ladder = {}

--[[
    Whether a hull, an axis-aligned box by its center and half size, and a
    ladder's oriented box overlap, touching counting as apart. It tests the
    world's axes and the box's own, which is exact for a ladder turned
    about the vertical alone and errs toward touching for one tilted
--]]

local function touches(box: Box, x: number, y: number, z: number, radius: number, half: number): boolean
	local center: vector = box.center
	local right: vector = box.right
	local up: vector = box.up
	local look: vector = box.look
	local boxX: number = box.size.x / 2
	local boxY: number = box.size.y / 2
	local boxZ: number = box.size.z / 2
	local ox: number = x - center.x
	local oy: number = y - center.y
	local oz: number = z - center.z

	-- The world's axes, against how far the box reaches along each
	if math.abs(ox) >= boxX * math.abs(right.x) + boxY * math.abs(up.x) + boxZ * math.abs(look.x) + radius then
		return false
	elseif math.abs(oy) >= boxX * math.abs(right.y) + boxY * math.abs(up.y) + boxZ * math.abs(look.y) + half then
		return false
	elseif math.abs(oz) >= boxX * math.abs(right.z) + boxY * math.abs(up.z) + boxZ * math.abs(look.z) + radius then
		return false
	end

	-- The box's axes, against how far the hull reaches along each
	local alongRight: number = math.abs(ox * right.x + oy * right.y + oz * right.z)
	local alongUp: number = math.abs(ox * up.x + oy * up.y + oz * up.z)
	local alongLook: number = math.abs(ox * look.x + oy * look.y + oz * look.z)

	return alongRight < boxX + radius * math.abs(right.x) + half * math.abs(right.y) + radius * math.abs(right.z)
		and alongUp < boxY + radius * math.abs(up.x) + half * math.abs(up.y) + radius * math.abs(up.z)
		and alongLook < boxZ + radius * math.abs(look.x) + half * math.abs(look.y) + radius * math.abs(look.z)
end

--[[
    The lowest id of the ladders a body's hull touches where it stands,
    and that ladder, or 0 and nil when it touches none
--]]

function Ladder.touching(state: State, world: World): (number, Ladder?)
	local settings: Settings = world.settings
	local half: number = Hulls.height(state, settings) / 2
	local feet: vector = state.position
	local lowest: number = 0
	local found: Ladder? = nil

	for _, ladder: Ladder in world.ladders do
		local lower: boolean = lowest == 0 or ladder.id < lowest
		if lower and touches(ladder.box, feet.x, feet.y + half, feet.z, settings.radius, half) then
			lowest = ladder.id
			found = ladder
		end
	end

	return lowest, found
end

-- Whether a ladder with this id is still registered
local function held(world: World, id: number): boolean
	for _, ladder: Ladder in world.ladders do
		if ladder.id == id then
			return true
		end
	end

	return false
end

--[[
    Mounts the ladder a body walks into while facing it, the lowest it
    touches. A body on the ground mounts only to climb up, never looking
    further below level than the game's ladder drop, so looking down at a
    ladder's foot never steps it on and off
--]]

function Ladder.mount(state: State, command: Command, world: World, forward: number)
	local drop: number = -world.settings.ladderDrop * DEGREES
	if forward <= 0 or (state.grounded and command.pitch < drop) then
		return
	end

	local id: number, ladder: Ladder? = Ladder.touching(state, world)
	if not ladder then
		return
	end

	-- Facing it: the box's center lies ahead along the body's level facing
	local feet: vector = state.position
	local center: vector = ladder.box.center
	local ahead: number = -(center.x - feet.x) * Math.sin(state.facing) - (center.z - feet.z) * Math.cos(state.facing)
	if ahead <= 0 then
		return
	end

	state.mode = "Ladder"
	state.ladder = id
	state.grounded = false
end

--[[
    A climber's tick, with no gravity: forward input climbs along the look
    plus up, losing the up part with the look further below level than the
    game's ladder drop, back input moves back along the look, and the
    velocity eases toward it at the game's ladder ease. A jump launches it
    off along its look at the game's ladder jump. Gives back whether it
    jumped

    @ speed | the tick's ladder speed, under the rules' cap
    @ jumping | whether a jump press the rules allow came this tick
--]]

function Ladder.run(
	state: State,
	command: Command,
	world: World,
	forward: number,
	speed: number,
	jumping: boolean
): boolean
	local settings: Settings = world.settings
	local delta: number = world.delta
	local sine: number = Math.sin(state.facing)
	local cosine: number = Math.cos(state.facing)
	local level: number = Math.cos(command.pitch)
	local lookX: number = -sine * level
	local lookY: number = Math.sin(command.pitch)
	local lookZ: number = -cosine * level

	-- A downed body lets go, and so does one whose ladder was taken out
	if state.posture == "Downed" or not held(world, state.ladder) then
		state.mode = "Air"
		state.ladder = 0

		return false
	end

	if jumping then
		local launch: number = settings.ladderJump
		state.velocity = vector.create(lookX * launch, lookY * launch, lookZ * launch)
		state.mode = "Air"
		state.ladder = 0
		Collide.move(state, state.velocity * delta, world)

		if state.grounded then
			state.mode = "Ground"
		end

		return true
	end

	local targetX: number, targetY: number, targetZ: number = 0, 0, 0
	if forward > 0 then
		local climbY: number = lookY
		if command.pitch >= -settings.ladderDrop * DEGREES then
			climbY += 1 -- The up direction's own height
		end

		local scale: number = forward * speed / math.sqrt(lookX * lookX + climbY * climbY + lookZ * lookZ)
		targetX, targetY, targetZ = lookX * scale, climbY * scale, lookZ * scale
	elseif forward < 0 then
		local scale: number = forward * speed
		targetX, targetY, targetZ = lookX * scale, lookY * scale, lookZ * scale
	end

	local ease: number = math.min(settings.ladderEase * delta, 1)
	local velocity: vector = state.velocity
	local vx: number = Math.lerp(velocity.x, targetX, ease)
	local vy: number = Math.lerp(velocity.y, targetY, ease)
	local vz: number = Math.lerp(velocity.z, targetZ, ease)
	local before: number = state.position.y

	state.velocity = vector.create(vx, vy, vz)
	state.grounded = false
	Collide.move(state, vector.create(vx * delta, vy * delta, vz * delta), world)

	-- Climbing down onto the ground stands it there
	if state.grounded then
		state.mode = "Ground"
		state.ladder = 0

		return false
	end

	local id: number = Ladder.touching(state, world)
	if id ~= 0 then
		state.ladder = id

		return false
	end

	-- Off its top, it steps ahead onto what is there, as a walk steps up and snaps to the ground
	state.ladder = 0
	if state.position.y > before then
		local step: number = speed * delta
		state.grounded = true
		Collide.move(state, vector.create(-sine * step, 0, -cosine * step), world)
	end

	if state.grounded then
		state.mode = "Ground"
	else
		state.mode = "Air"
	end

	return false
end

return Ladder
