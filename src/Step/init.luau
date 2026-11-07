--[[
    The shared step: one tick of a body in place from its command, the same
    on the server, in the owner's prediction and for NPCs, ending with the
    whole state at OwnerState's precisions
--]]

--!strict
--!native
local Collide = require(script.Collide)
local Constants = require(script.Parent.Constants)
local Hulls = require(script.Hulls)
local Ladder = require(script.Ladder)
local Mantle = require(script.Mantle)
local Math = require(script.Math)
local State = require(script.State)
local Swim = require(script.Swim)

local SKIN: number = Constants.SKIN
local ANGLE_STEPS: number = Constants.ANGLE_STEPS
local LEAN_STEPS: number = Constants.LEAN_STEPS
local EYE_QUANTUM: number = Constants.EYE_QUANTUM
local COUNTERS: number = 2 ^ Constants.COUNTER_BITS -- The jump and land counters wrap here
local TURN: number = 2 * math.pi -- Radians a turn, which a u16 angle counts in ANGLE_STEPS
local TIMER_LIMIT: number = Constants.TIMER_LIMIT
local EXACT_EVERY: number = Constants.EXACT_EVERY
local CUT: number = Constants.POSITION_QUANTUM -- How far short of its move a rise ends when cut, past float32 rounding
local AIR: Enum.Material = Enum.Material.Air -- The ground's material off the ground
local WATER: Enum.Material = Enum.Material.Water -- The material a body meets entering water

type Allow = State.Allow
type Command = State.Command
type Mode = State.Mode
type MoveMode = State.MoveMode
type RuleStep = State.RuleStep
type Settings = State.Settings
type State = State.State
type World = State.World

-- One mode's tick, which the dispatch runs by the body's mode
type Run = (state: State, command: Command, world: World) -> ()

local Step = {}

-- This tick's look and move, set before the mode's tick runs, which every mode reads
local sine: number, cosine: number = 0, 1 -- Of the command's yaw
local moveForward: number, moveRight: number = 0, 0 -- The move axes, no longer than 1 together
local speed: number = 0 -- The tick's speed, its mode's stance under the rules' cap
local targetX: number, targetZ: number = 0, 0 -- The level velocity the move asks for, at the tick's speed
local jumping: boolean = false -- Whether the press and the rules make this tick jump
local landed: number = 0 -- The speed this tick landed at, 0 for no landing that counted
local surface: number? = nil -- The water's surface over the body, where its tick starts and then where its move ends
local deep: boolean = false -- Whether the tick starts with the feet deeper in water than a crouch is allowed

-- What the rules function reads and what it permits, filled each tick so a step makes no table
local RuleInput: RuleStep = {} :: RuleStep
local RuleAllow: Allow = { jump = false, sprint = false, crouch = false, stand = false }

-- A value less itself is 0 only when the value is finite
local function finite(value: number): boolean
	return value - value == 0
end

--[[
    Refuses a command the step cannot run: a move axis past -1 to 1, any
    input that is not finite, or no presses set beside its levels
--]]

local function check(command: Command)
	if not finite(command.forward) or math.abs(command.forward) > 1 then
		error(`A command's forward must be a finite number from -1 to 1, and got {command.forward}`)
	elseif not finite(command.right) or math.abs(command.right) > 1 then
		error(`A command's right must be a finite number from -1 to 1, and got {command.right}`)
	elseif not finite(command.yaw) then
		error(`A command's yaw must be finite, and got {command.yaw}`)
	elseif not finite(command.pitch) then
		error(`A command's pitch must be finite, and got {command.pitch}`)
	elseif not finite(command.lean) then
		error(`A command's lean must be finite, and got {command.lean}`)
	elseif not finite(command.headYaw) then
		error(`A command's head yaw must be finite, and got {command.headYaw}`)
	elseif not finite(command.headPitch) then
		error(`A command's head pitch must be finite, and got {command.headPitch}`)
	elseif type(command.pressed) ~= "table" then
		error(`A command needs the presses its handler derived, and got a {typeof(command.pressed)}`)
	end
end

--[[
    The tick's look: the facing from the command's yaw, which a mantle
    holds instead, the head offset clamped in place to the game's cone, the
    lean held to its limit and its rate and to 0 while the head offset is
    not, and the move axes scaled back to a length of 1, so a longer move
    gains nothing
--]]

local function face(state: State, command: Command, settings: Settings, delta: number)
	-- A mantle's path runs along the facing it started with
	if state.mode ~= "Mantle" then
		state.facing = command.yaw
	end

	sine = Math.sin(command.yaw)
	cosine = Math.cos(command.yaw)

	local cone: number = settings.headCone
	command.headYaw = math.clamp(command.headYaw, -cone, cone)
	command.headPitch = math.clamp(command.headPitch, -cone, cone)

	if command.headYaw ~= 0 or command.headPitch ~= 0 then
		state.lean = 0
	else
		local limit: number = settings.lean
		local most: number = settings.leanRate * delta
		local wanted: number = math.clamp(command.lean, -limit, limit)
		state.lean = math.clamp(wanted, state.lean - most, state.lean + most)
	end

	local forward: number, right: number = command.forward, command.right
	local length: number = math.sqrt(forward * forward + right * right)
	if length > 1 then
		forward /= length
		right /= length
	end

	moveForward, moveRight = forward, right
end

--[[
    Runs the game's rules function on what Tread's own physics permits: a
    jump only on the ground or a ladder, sprint only standing, a crouch for
    any posture but downed with the feet no deeper than a crouch allows,
    and a stand for any posture but downed. Gives back the speed cap it
    returns
--]]

local function rule(state: State, command: Command, world: World): number
	RuleInput.command = command
	RuleInput.pressed = command.pressed
	RuleInput.grounded = state.grounded
	RuleInput.mode = state.mode
	RuleInput.posture = state.posture
	RuleInput.airTicks = state.airTicks
	RuleInput.groundTicks = state.groundTicks
	RuleInput.fields = state.fields
	RuleInput.held = state.held
	RuleInput.block = state.block
	RuleInput.isNpc = state.npc

	RuleAllow.jump = state.grounded or state.mode == "Ladder"
	RuleAllow.sprint = state.posture == "Stand"
	RuleAllow.crouch = state.posture ~= "Downed" and not deep
	RuleAllow.stand = state.posture ~= "Downed"

	local cap: number = world.rules(RuleInput, RuleAllow)
	if type(cap) ~= "number" or not (cap >= 0) then
		error(`The rules function must return a speed cap of 0 or more, and got {cap}`)
	end

	return cap
end

--[[
    Whether a crouched body has room to stand where it is: the standing
    hull, with a skin over its top so it keeps one under a ceiling, clear
    of the world and of the other live hulls
--]]

local function roomToStand(state: State, world: World): boolean
	local settings: Settings = world.settings
	local width: number = settings.radius + settings.radius
	local height: number = settings.standing + SKIN
	local feet: vector = state.position
	local center: vector = vector.create(feet.x, feet.y + height / 2, feet.z)

	if not Collide.clear(center, vector.create(width, height, width), world) then
		return false
	end

	state.posture = "Stand"
	local blocked: boolean = Hulls.block(state, world)
	state.posture = "Crouch"

	return not blocked
end

--[[
    Posture follows the crouch level, or a crouch press carried in, with
    the feet kept in place, and water too deep for a crouch refuses it.
    Standing up takes the rules' permit and room for the standing hull, and
    downed is the game's to set and clear
--]]

local function pose(state: State, command: Command, world: World)
	local crouching: boolean = (command.crouch or command.pressed.crouch) and not deep

	if state.posture == "Stand" then
		if crouching and RuleAllow.crouch then
			state.posture = "Crouch"
		end
	elseif state.posture == "Crouch" then
		if not crouching and RuleAllow.stand and roomToStand(state, world) then
			state.posture = "Stand"
		end
	end
end

--[[
    A body left standing on another's hull top slides off it outward at the
    game's head slide, away from the other's center, or ahead along its
    facing when it stands dead on it, so it may jump from a head but never
    rest there
--]]

local function slideOff(state: State, world: World, below: State?)
	local slide: number = world.settings.headSlide
	if not below or not state.grounded or not (slide > 0) then
		return
	end

	local at: vector = state.position
	local under: vector = below.position
	local awayX: number = at.x - under.x
	local awayZ: number = at.z - under.z
	local apart: number = math.sqrt(awayX * awayX + awayZ * awayZ)

	if apart > 0 then
		awayX /= apart
		awayZ /= apart
	else
		awayX, awayZ = -sine, -cosine
	end

	local reach: number = slide * world.delta
	Collide.move(state, vector.create(awayX * reach, 0, awayZ * reach), world)

	if not state.grounded then
		state.mode = "Air"
	end
end

--[[
    A landing, which counts only after the game's landing airtime: it adds
    to the land counter, is heavy when it met the ground faster than any
    jump on level ground lands, and keeps that speed for the tick's caller
--]]

local function land(state: State, world: World, falling: number)
	local settings: Settings = world.settings
	if state.airTicks < math.round(settings.landing / world.delta) then
		return
	end

	-- A jump on level ground lands under its own speed plus the one tick of gravity its last tick adds
	local fastestJump: number = settings.jump + settings.gravity * world.delta

	state.lands = (state.lands + 1) % COUNTERS
	state.heavy = falling >= fastestJump
	landed = falling
end

--[[
    A rise something above cut short ends there: when a move up from feet
    at from came short of up, a ceiling, an overhang or another body's hull
    stopped it, so the upward speed drops to 0 and the body falls from the
    next tick
--]]

local function bump(state: State, from: number, up: number)
	local velocity: vector = state.velocity
	if up > 0 and velocity.y > 0 and state.position.y - from < up - CUT then
		state.velocity = vector.create(velocity.x, 0, velocity.z)
	end
end

--[[
    Ground: the level velocity set to the move at once, a jump taking the
    body into the air and ending its rise against anything above, then the
    walk with its step up and snap, or the fall a jump starts
--]]

local function ground(state: State, _: Command, world: World)
	local settings: Settings = world.settings
	local delta: number = world.delta
	local rise: number = 0

	if jumping then
		rise = settings.jump
		state.grounded = false
		state.jumps = (state.jumps + 1) % COUNTERS
	end

	local from: number = state.position.y
	state.velocity = vector.create(targetX, rise, targetZ)
	local below: State? = Collide.move(state, vector.create(targetX * delta, rise * delta, targetZ * delta), world)
	bump(state, from, rise * delta)

	if state.grounded then
		state.mode = "Ground"
	else
		state.mode = "Air"
	end

	slideOff(state, world, below)
end

--[[
    Air: the level velocity eased toward the move at the game's air ease,
    gravity to the terminal speed or a jump the rules allow, then the fall
    with its ground probe, a rise ended against anything above, and a
    landing when it finds ground
--]]

local function air(state: State, _: Command, world: World)
	local settings: Settings = world.settings
	local delta: number = world.delta
	local velocity: vector = state.velocity
	local ease: number = math.min(settings.airEase * delta, 1)
	local vx: number = Math.lerp(velocity.x, targetX, ease)
	local vz: number = Math.lerp(velocity.z, targetZ, ease)
	local vy: number

	if jumping then
		vy = settings.jump
		state.jumps = (state.jumps + 1) % COUNTERS
	else
		vy = math.max(velocity.y - settings.gravity * delta, -settings.terminal)
	end

	local from: number = state.position.y
	state.velocity = vector.create(vx, vy, vz)
	local below: State? = Collide.move(state, vector.create(vx * delta, vy * delta, vz * delta), world)
	bump(state, from, vy * delta)
	if not state.grounded then
		return
	end

	state.mode = "Ground"
	land(state, world, -vy)
	slideOff(state, world, below)
end

-- Swim: the tick's move along the look from the water where the tick started
local function swim(state: State, command: Command, world: World)
	Swim.run(state, command, world, surface, moveForward, moveRight, speed)
end

-- Ladder: the climb, and a jump off it, which the jump counter counts
local function ladder(state: State, command: Command, world: World)
	if Ladder.run(state, command, world, moveForward, speed, jumping) then
		state.jumps = (state.jumps + 1) % COUNTERS
	end
end

-- Each mode's tick by its name, which a mode outside it errors naming
local MODES: { [Mode]: Run } = {
	Ground = ground,
	Air = air,
	Swim = swim,
	Ladder = ladder,
	Mantle = Mantle.run,
}

--[[
    Into a mantle or onto a ladder before the move, from the ground, the air
    or the water and never downed: a jump press tries the mantle, and a walk
    into a ladder's box while facing it starts the climb
--]]

local function enter(state: State, command: Command, world: World)
	local mode: Mode = state.mode
	if state.posture == "Downed" or (mode ~= "Ground" and mode ~= "Air" and mode ~= "Swim") then
		return
	end

	if command.pressed.jump then
		Mantle.start(state, world)
	else
		Ladder.mount(state, command, world, moveForward)
	end
end

--[[
    Into and out of the water after the move. Feet in water at least the
    game's swim depth deep start a swim, keeping the game's entry share of
    the velocity, and a fall that ends there lands with water as its
    material. A swimmer leaves once the water is shallower than the leave
    depth or its feet are out, standing up where the standing hull fits
--]]

local function wade(state: State, world: World)
	local mode: Mode = state.mode
	if mode ~= "Ground" and mode ~= "Air" and mode ~= "Swim" then
		return
	end

	local settings: Settings = world.settings
	local top: number? = surface
	local feet: vector = state.position

	if mode == "Swim" then
		if top and feet.y < top and Swim.depth(state, world, top) >= settings.swimLeave then
			return
		end

		if state.grounded then
			state.mode = "Ground"
		else
			state.mode = "Air"
		end

		-- The standing hull returns with the posture, which needs its room
		if state.posture == "Stand" then
			state.posture = "Crouch"
			if roomToStand(state, world) then
				state.posture = "Stand"
			end
		end

		return
	end

	if not top or feet.y >= top or Swim.depth(state, world, top) < settings.swimEnter then
		return
	end

	if mode == "Air" then
		land(state, world, -state.velocity.y)
	end

	state.velocity *= settings.waterEntry
	state.mode = "Swim"
	state.grounded = false
	state.groundNormal = vector.zero
	state.groundMaterial = WATER
end

--[[
    Tread's timers and the fall apex: a tick that ends on the ground adds
    to the ground ticks and clears the air ticks, one in the air the other
    way round, and the apex follows the body up from its last ground. In
    water or on a ladder both stay clear, and the apex follows the body
    from the tick after it got there, which keeps a landing's apex
--]]

local function count(state: State, wasGrounded: boolean, wasMode: Mode)
	local mode: Mode = state.mode
	if mode == "Swim" or mode == "Ladder" then
		state.airTicks = 0
		state.groundTicks = 0

		if wasMode == mode then
			state.apex = state.position.y
		end
	elseif state.grounded then
		state.groundTicks += 1
		state.airTicks = 0

		-- The landing tick keeps its fall's apex for the landing's readers
		if wasGrounded then
			state.apex = state.position.y
		end
	else
		state.airTicks += 1
		state.groundTicks = 0
		state.apex = math.max(state.apex, state.position.y)
	end
end

--[[
    A walking body's tick: depenetration, exact at every tenth command,
    the water where it starts, the rules' cap and permits, posture and a
    mantle or a ladder to enter, then its mode's move at that mode's
    stance, the water where the move ends, and the timers. A mantle runs
    its path with no posture or entry. Gives back how far it sank when no
    spot was clear
--]]

local function walk(state: State, command: Command, world: World): number?
	local settings: Settings = world.settings
	local stuck: number? = Collide.depenetrate(state, world, command.number % EXACT_EVERY == 0)

	surface = Swim.surface(state, world)
	local top: number? = surface
	deep = top ~= nil and top - state.position.y > settings.crouchDepth

	local cap: number = rule(state, command, world)
	if state.mode ~= "Mantle" then
		pose(state, command, world)
		enter(state, command, world)
	end

	local mode: Mode = state.mode
	local sprinting: boolean = command.sprint and RuleAllow.sprint
	local stance: number = settings.walk
	if mode == "Swim" then
		stance = settings.swim
		if sprinting then
			stance = settings.swimSprint
		end
	elseif mode == "Ladder" then
		stance = settings.ladder
		if sprinting then
			stance = settings.ladderSprint
		end
	elseif state.posture ~= "Stand" then
		stance = settings.crouch
	elseif sprinting then
		stance = settings.sprint
	end

	speed = math.min(stance, cap)
	targetX = (moveRight * cosine - moveForward * sine) * speed
	targetZ = -(moveRight * sine + moveForward * cosine) * speed
	jumping = command.pressed.jump and RuleAllow.jump
	state.sprint = sprinting
	state.aim = command.aim

	local run: Run? = MODES[mode]
	if not run then
		error(`The step has no mode {mode}`)
	end

	local wasGrounded: boolean = state.grounded
	run(state, command, world)

	surface = Swim.surface(state, world)
	wade(state, world)
	count(state, wasGrounded, mode)

	return stuck
end

--[[
    Noclip: the body flies along the whole look at the walk or sprint speed
    and through every surface, with no gravity, no ground, no ladder, no
    fall to count and no rules, which only the staff modes skip
--]]

local function noclip(state: State, command: Command, world: World)
	local settings: Settings = world.settings
	local delta: number = world.delta
	local flying: number = command.sprint and settings.sprint or settings.walk
	local ahead: number = moveForward * Math.cos(command.pitch)

	local vx: number = (moveRight * cosine - ahead * sine) * flying
	local vy: number = moveForward * Math.sin(command.pitch) * flying
	local vz: number = -(moveRight * sine + ahead * cosine) * flying
	local at: vector = state.position

	state.velocity = vector.create(vx, vy, vz)
	state.position = vector.create(at.x + vx * delta, at.y + vy * delta, at.z + vz * delta)
	state.mode = "Air"
	state.ladder = 0
	state.grounded = false
	state.groundNormal = vector.zero
	state.groundMaterial = AIR
	state.sprint = command.sprint
	state.aim = command.aim
	state.airTicks = 0
	state.groundTicks = 0
	state.apex = state.position.y
end

--[[
    Parked: the body holds still where it is, whatever its command says,
    with no fall to count, and a mantle it was in ends there
--]]

local function park(state: State)
	if state.mode == "Mantle" then
		Mantle.cancel(state)
	end

	state.velocity = vector.zero
	state.sprint = false
	state.aim = false
	state.airTicks = 0
	state.apex = state.position.y
end

--[[
    The eye eases toward its posture's height at the game's eye ease, a
    swimmer's the crouched one, by at least a quantum a tick until it is
    there, while the hull changes size at once
--]]

local function ease(state: State, world: World)
	local settings: Settings = world.settings
	local target: number = settings.eyeCrouched
	if state.posture == "Stand" and state.mode ~= "Swim" then
		target = settings.eyeStanding
	elseif state.posture == "Downed" then
		target = settings.eyeDowned
	end

	target = Math.quantizeEye(target)

	local previous: number = state.eyeHeight
	local share: number = math.min(settings.eyeEase * world.delta, 1)
	local eased: number = Math.quantizeEye(Math.lerp(previous, target, share))

	-- Too near for the ease to move it a whole quantum, so it takes one
	if eased == previous and previous ~= target then
		eased = previous + math.sign(target - previous) * EYE_QUANTUM
	end

	state.eyeHeight = eased
end

--[[
    Rounds the whole state to OwnerState's precisions, so the owner's replay
    starts from exactly what the server sent: position, apex and the last
    ground's height to 1/512 stud, velocity to 1/64 stud a second, facing to
    a u16 angle, lean to its i8 steps, the eye and the mantle's rise to 1/32
    stud, and each timer to its u8
--]]

local function quantize(state: State, settings: Settings)
	local at: vector = state.position
	local velocity: vector = state.velocity
	state.position = vector.create(Math.quantize(at.x), Math.quantize(at.y), Math.quantize(at.z))
	state.velocity = vector.create(
		Math.quantizeVelocity(velocity.x),
		Math.quantizeVelocity(velocity.y),
		Math.quantizeVelocity(velocity.z)
	)

	local angle: number = math.round(state.facing / TURN * ANGLE_STEPS) % ANGLE_STEPS
	state.facing = angle * TURN / ANGLE_STEPS

	local limit: number = settings.lean
	if limit > 0 then
		state.lean = math.round(state.lean / limit * LEAN_STEPS) * limit / LEAN_STEPS
	else
		state.lean = 0
	end

	state.apex = Math.quantize(state.apex)
	state.groundHeight = Math.quantize(state.groundHeight)
	state.eyeHeight = Math.quantizeEye(state.eyeHeight)
	state.mantleRise = Math.quantizeEye(state.mantleRise)
	state.groundTicks = math.min(state.groundTicks, TIMER_LIMIT)
	state.airTicks = math.min(state.airTicks, TIMER_LIMIT)
	state.mantleTicks = math.min(state.mantleTicks, TIMER_LIMIT)
end

--[[
    Moves a body one tick in place from its command and the world, the
    same on every realm, allocating nothing: its look, then its move mode's
    move, the eye eased, the water level, and the whole state rounded to
    OwnerState's precisions. The command's head offset is clamped to the
    game's cone in place, and a move mode other than walking ends a mantle.
    Gives back the speed the body landed at, 0 for no landing that counted,
    and how far it sank when depenetration found no clear spot, nil when it
    is clear
--]]

function Step.advance(state: State, command: Command, world: World): (number, number?)
	check(command)

	local settings: Settings = world.settings
	local moveMode: MoveMode = state.moveMode
	local stuck: number? = nil

	state.command = command.number
	state.tick = world.tick
	landed = 0

	if moveMode == "Walk" then
		face(state, command, settings, world.delta)
		stuck = walk(state, command, world)
		ease(state, world)
		state.waterLevel = Swim.level(state, surface)
	elseif moveMode == "Noclip" then
		if state.mode == "Mantle" then
			Mantle.cancel(state)
		end

		face(state, command, settings, world.delta)
		noclip(state, command, world)
		surface = Swim.surface(state, world)
		ease(state, world)
		state.waterLevel = Swim.level(state, surface)
	elseif moveMode == "Parked" then
		park(state)
	else
		error(`The step has no move mode {moveMode}`)
	end

	quantize(state, settings)

	return landed, stuck
end

return Step
