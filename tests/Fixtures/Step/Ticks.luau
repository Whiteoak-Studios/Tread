--[[
    The trials the step's cases and its live scenario both run through
    Step.advance and Eye.clear on the fixture geometry and its ceiling, each
    from a fixed state with fixed commands and the ending it must reach
--]]

--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Casts = require(script.Parent.Collision)
local Ceiling = require(script.Parent.Ceiling)
local Constants = require(ReplicatedStorage.Packages.Tread.Constants)
local Eye = require(ReplicatedStorage.Packages.Tread.Step.Eye)
local Geometry = require(script.Parent.Geometry)
local Math = require(ReplicatedStorage.Packages.Tread.Step.Math)
local Scene = require(script.Parent.Scene)
local State = require(ReplicatedStorage.Packages.Tread.Step.State)
local Step = require(ReplicatedStorage.Packages.Tread.Step)
local World = require(ReplicatedStorage.Packages.Tread.Step.World)

local SIMULATION_RATE: number = 20 -- Frontier Zero's rates.simulation, in Hz
local SKIN: number = Constants.SKIN
local TOLERANCE: number = SKIN / 4 -- How far an ending may sit from where it should, well inside the skin it keeps
local FLOOR: number = Geometry.floor
local RESTING: number = FLOOR + SKIN -- Feet at rest on the floor
local WEST: number = math.pi / 2 -- A yaw that looks along -X
local EAST: number = -math.pi / 2 -- A yaw that looks along +X
local COYOTE: number = 2 -- Air ticks the coyote rules still allow a jump in, as Frontier Zero's do

local SETTINGS = Scene.settings
local RADIUS: number = SETTINGS.radius
local STANDING: number = SETTINGS.standing
local WALK: number = SETTINGS.walk
local STANDING_EYE: number = Math.quantizeEye(SETTINGS.eyeStanding) -- The eye a standing body eases to, on its quanta
local CROUCHED_EYE: number = Math.quantizeEye(SETTINGS.eyeCrouched)

type Allow = State.Allow
type Collision = State.Collision
type Command = State.Command
type Part = Geometry.Part
type RuleStep = State.RuleStep
type Rules = State.Rules
type State = State.State
type World = State.World

type Trial = {
	name: string,
	run: (collision: Collision) -> string?, -- Why it ended away from where it should, or nil
}

-- A command that changes a fresh one before a refusal is tried on it
type Change = {
	label: string,
	set: (order: Command) -> (),
	refusal: string,
}

-- What a rules function under test gives back in place of a speed cap
type Return = {
	label: string,
	give: () -> any,
}

local Ticks = {}

-- Why a value ended away from where it should, or nil
local function near(label: string, got: number, want: number): string?
	if math.abs(got - want) <= TOLERANCE then
		return nil
	end

	return `{label} ended at {got}, where {want} was expected`
end

-- Why a value is not exactly what it should be, or nil
local function is(label: string, got: any, want: any): string?
	if got == want then
		return nil
	end

	return `{label} was {got}, where {want} was expected`
end

-- A rules function that refuses nothing and caps no speed
local function free(_: RuleStep, _: Allow): number
	return math.huge
end

-- A server's world over a collision at Frontier Zero's simulation rate, with a rules function of the trial's own
local function newWorld(collision: Collision, rules: Rules?): World
	return World.new(SETTINGS, SIMULATION_RATE, collision, nil, rules or free, true)
end

-- A command with no input, numbered 1, its presses all off
local function newCommand(): Command
	return {
		number = 1,
		forward = 0,
		right = 0,
		jump = false,
		crouch = false,
		sprint = false,
		aim = false,
		pressed = { jump = false, crouch = false, sprint = false, aim = false },
		yaw = 0,
		pitch = 0,
		lean = 0,
		headYaw = 0,
		headPitch = 0,
		fields = {},
	}
end

--[[
    Steps a body for ticks on one command, numbered on from its own, its
    presses off after the first tick as a handler derives them, and gives
    back the speed of the last landing that counted, 0 for none
--]]

local function advance(state: State, world: World, order: Command, ticks: number): number
	local landing: number = 0

	for _ = 1, ticks do
		local speed: number, _: number? = Step.advance(state, order, world)
		if speed > 0 then
			landing = speed
		end

		order.number += 1
		order.pressed.jump = false
		order.pressed.crouch = false
		order.pressed.sprint = false
		order.pressed.aim = false
	end

	return landing
end

-- A lean on the i8 steps a state's lean ends each step on
local function leanSteps(value: number): number
	return math.round(value / SETTINGS.lean * Constants.LEAN_STEPS) * SETTINGS.lean / Constants.LEAN_STEPS
end

-- Why a step that should refuse ran, or failed with another message, or nil
local function refuses(label: string, refusal: string, ran: boolean, message: any): string?
	if ran then
		return `the step took {label}`
	elseif not string.find(`{message}`, refusal, 1, true) then
		return `the step's refusal of {label} was something other than "{refusal}": {message}`
	end

	return nil
end

local TRIALS: { Trial } = {
	{
		-- A walk ahead at yaw 0 moves along -Z at the walk speed, set at once, on the ground the whole way
		name = "walkForward",
		run = function (collision: Collision): string?
			local world: World = newWorld(collision)
			local state: State = Scene.state(vector.create(-20, RESTING, 25), true)
			local order: Command = newCommand()
			order.forward = 1
			advance(state, world, order, 10)

			local at: vector = state.position

			return near("x", at.x, -20)
				or near("z", at.z, 20)
				or near("y", at.y, RESTING)
				or is("the velocity's z", state.velocity.z, -WALK)
				or is("grounded", state.grounded, true)
				or is("the mode", state.mode, "Ground")
		end,
	},

	{
		-- Turned a quarter turn, the same walk goes along -X instead, through the step's own sine and cosine
		name = "turnedWalk",
		run = function (collision: Collision): string?
			local world: World = newWorld(collision)
			local state: State = Scene.state(vector.create(-20, RESTING, 15), true)
			local order: Command = newCommand()
			order.forward = 1
			order.yaw = WEST
			advance(state, world, order, 10)

			local at: vector = state.position

			return near("x", at.x, -25) or near("z", at.z, 15) or near("the facing", state.facing, WEST)
		end,
	},

	{
		-- A move input longer than 1 gains nothing: its diagonal ends where one scaled to a length of 1 does
		name = "longMove",
		run = function (collision: Collision): string?
			local world: World = newWorld(collision)
			local long: State = Scene.state(vector.create(-20, RESTING, 0), true)
			local unit: State = Scene.state(vector.create(-20, RESTING, 0), true)
			local longOrder: Command = newCommand()
			local unitOrder: Command = newCommand()
			longOrder.forward, longOrder.right = 1, 1
			unitOrder.forward, unitOrder.right = math.sqrt(0.5), math.sqrt(0.5)

			advance(long, world, longOrder, 10)
			advance(unit, world, unitOrder, 10)

			-- Each axis of the velocity rounds to its own quantum, so the speed is held to within one
			local velocity: vector = long.velocity
			local speed: number = math.sqrt(velocity.x * velocity.x + velocity.z * velocity.z)
			if math.abs(speed - WALK) > Constants.VELOCITY_QUANTUM then
				return `the long move ran at {speed}, where the walk's {WALK} was expected`
			end

			return near("the long move's x", long.position.x, unit.position.x)
				or near("the long move's z", long.position.z, unit.position.z)
		end,
	},

	{
		-- One jump press leaves the ground at the jump speed, counts one jump and one landing back on the floor,
		-- light, at a speed under a jump's own plus one tick of gravity
		name = "jumpLand",
		run = function (collision: Collision): string?
			local world: World = newWorld(collision)
			local state: State = Scene.state(vector.create(-20, RESTING, -10), true)
			local order: Command = newCommand()
			order.jump = true
			order.pressed.jump = true

			local landing: number, apex: number = 0, 0
			for _ = 1, 30 do
				local speed: number = advance(state, world, order, 1)
				if speed > 0 then
					landing = speed
					apex = state.apex
				end
			end

			-- A jump rises its speed squared over twice gravity, and the tick it leaves on moves at the whole speed
			local most: number = SETTINGS.jump + SETTINGS.gravity * world.delta
			local rise: number = SETTINGS.jump * SETTINGS.jump / (2 * SETTINGS.gravity)
			local highest: number = rise + SETTINGS.jump * world.delta
			if landing <= 0 then
				return "it never landed with a landing that counted"
			elseif landing >= most then
				return `it landed at {landing}, past the {most} a jump on level ground never reaches`
			elseif apex - RESTING < rise or apex - RESTING > highest then
				return `its apex was {apex - RESTING} above the floor, outside {rise} to {highest}`
			end

			return is("the jumps", state.jumps, 1)
				or is("the landings", state.lands, 1)
				or is("heavy", state.heavy, false)
				or is("grounded", state.grounded, true)
				or near("y", state.position.y, RESTING)
		end,
	},

	{
		-- A fall from 10 studs lands heavy, faster than any jump lands on level ground
		name = "fallHeavy",
		run = function (collision: Collision): string?
			local world: World = newWorld(collision)
			local state: State = Scene.state(vector.create(-20, FLOOR + 10, -14), false)
			local landing: number = advance(state, world, newCommand(), 40)

			local most: number = SETTINGS.jump + SETTINGS.gravity * world.delta
			if landing <= most then
				return `it landed at {landing}, where a fall from 10 studs lands past {most}`
			end

			return is("the landings", state.lands, 1)
				or is("heavy", state.heavy, true)
				or is("the mode", state.mode, "Ground")
				or near("y", state.position.y, RESTING)
		end,
	},

	{
		-- A drop of half a stud lands inside the game's landing airtime, so it counts no landing
		name = "curbLanding",
		run = function (collision: Collision): string?
			local world: World = newWorld(collision)
			local state: State = Scene.state(vector.create(-20, RESTING + 0.5, -14), false)
			local landing: number = advance(state, world, newCommand(), 6)

			return is("the landing speed", landing, 0)
				or is("the landings", state.lands, 0)
				or is("grounded", state.grounded, true)
				or near("y", state.position.y, RESTING)
		end,
	},

	{
		-- In the air the level velocity moves toward the move at the air ease, 3 a second, and gravity pulls it down
		name = "airEase",
		run = function (collision: Collision): string?
			local world: World = newWorld(collision)
			local state: State = Scene.state(vector.create(-20, FLOOR + 20, -10), false)
			local order: Command = newCommand()
			order.forward = 1

			-- A fifteenth of the way from 0 toward -10, then from there, each on the 1/64 stud a second quanta
			advance(state, world, order, 1)
			local first: string? = is("the first tick's velocity z", state.velocity.z, -1.5)
				or is("the first tick's velocity y", state.velocity.y, -3.40625)
			if first then
				return first
			end

			advance(state, world, order, 1)

			return is("the second tick's velocity z", state.velocity.z, -2.78125)
				or is("grounded", state.grounded, false)
		end,
	},

	{
		-- Crouching keeps the feet where they are while the eye eases down to the crouched height, and letting go
		-- of crouch stands back up and eases it back
		name = "crouchStand",
		run = function (collision: Collision): string?
			local world: World = newWorld(collision)
			local state: State = Scene.state(vector.create(-20, RESTING, -12), true)
			state.eyeHeight = STANDING_EYE
			local order: Command = newCommand()
			order.crouch = true
			order.pressed.crouch = true

			advance(state, world, order, 1)
			local down: string? = is("the posture", state.posture, "Crouch")
				or is("the first tick's eye", state.eyeHeight, 3.34375)
				or near("y", state.position.y, RESTING)
			if down then
				return down
			end

			advance(state, world, order, 11)
			local crouched: string? = is("the crouched eye", state.eyeHeight, CROUCHED_EYE)
			if crouched then
				return crouched
			end

			order.crouch = false
			advance(state, world, order, 1)
			local up: string? = is("the posture", state.posture, "Stand")
			if up then
				return up
			end

			advance(state, world, order, 11)

			return is("the standing eye", state.eyeHeight, STANDING_EYE)
		end,
	},

	{
		-- Under the ceiling a crouched body cannot stand, and walking out it stands once its standing hull clears
		name = "ceilingStand",
		run = function (collision: Collision): string?
			local ceiling: Part = Ceiling.ceiling
			local world: World = newWorld(collision)
			local state: State = Scene.state(vector.create(ceiling.center.x, RESTING, ceiling.center.z), true)
			state.posture = "Crouch"
			state.eyeHeight = CROUCHED_EYE
			local order: Command = newCommand()

			advance(state, world, order, 1)
			if state.posture ~= "Crouch" then
				return "it stood up under the ceiling"
			end

			order.forward = 1
			order.yaw = WEST

			local stoodAt: number? = nil
			for _ = 1, 30 do
				local before: number = state.position.x
				advance(state, world, order, 1)

				if not stoodAt and state.posture == "Stand" then
					stoodAt = before
				end
			end

			local edge: number = ceiling.center.x - ceiling.size.x / 2 - RADIUS
			if not stoodAt then
				return "it never stood up once clear of the ceiling"
			elseif stoodAt > edge + TOLERANCE then
				return `it stood up at x {stoodAt}, under the ceiling, whose edge its hull clears at {edge}`
			end

			return nil
		end,
	},

	{
		-- A lean past the game's 20° limit stops at it, 10° a tick at the 200° a second lean rate, either way
		name = "lean",
		run = function (collision: Collision): string?
			local world: World = newWorld(collision)
			local state: State = Scene.state(vector.create(-20, RESTING, -12), true)
			local order: Command = newCommand()
			order.lean = 30

			advance(state, world, order, 1)
			local first: string? = is("the first tick's lean", state.lean, leanSteps(10))
			if first then
				return first
			end

			advance(state, world, order, 1)
			local full: string? = is("the full lean", state.lean, SETTINGS.lean)
			if full then
				return full
			end

			order.lean = -30
			advance(state, world, order, 5)

			return is("the full lean the other way", state.lean, -SETTINGS.lean)
		end,
	},

	{
		-- A head offset past the game's 75° cone is clamped to it in the command, and lean is zeroed while it is set
		name = "headCone",
		run = function (collision: Collision): string?
			local world: World = newWorld(collision)
			local state: State = Scene.state(vector.create(-20, RESTING, -12), true)
			state.lean = SETTINGS.lean
			local order: Command = newCommand()
			order.lean = SETTINGS.lean
			order.headYaw = 100
			order.headPitch = -90

			advance(state, world, order, 1)
			local clamped: string? = is("the head yaw", order.headYaw, SETTINGS.headCone)
				or is("the head pitch", order.headPitch, -SETTINGS.headCone)
				or is("the lean while the head offset is set", state.lean, 0)
			if clamped then
				return clamped
			end

			order.headYaw = 0
			order.headPitch = 0
			advance(state, world, order, 1)

			return is("the lean once the head offset is cleared", state.lean, leanSteps(10))
		end,
	},

	{
		-- In open air the cleared eye is the wanted eye: half a lean left, facing -X, shifts it half the game's
		-- shift sideways along +Z and half its drop down
		name = "eyeOpen",
		run = function (collision: Collision): string?
			local world: World = newWorld(collision)
			local feet: vector = vector.create(-20, RESTING, -12)
			local state: State = Scene.state(feet, true)
			state.eyeHeight = STANDING_EYE
			state.facing = WEST
			state.lean = -SETTINGS.lean / 2

			local shift: Vector3 = SETTINGS.leanShift
			local eye: vector = Eye.clear(state, world)

			return near("the eye's x", eye.x, feet.x)
				or near("the eye's y", eye.y, feet.y + STANDING_EYE + shift.Y / 2)
				or near("the eye's z", eye.z, feet.z + shift.X / 2)
		end,
	},

	{
		-- Against the wall, leaning into it, the eye holds the clearance from the wall's face behind the head's center
		name = "eyeWall",
		run = function (collision: Collision): string?
			local wall: Part = Geometry.wall
			local face: number = wall.center.x - wall.size.x / 2
			local world: World = newWorld(collision)
			local feet: vector = vector.create(face - RADIUS - SKIN, RESTING, wall.center.z)
			local state: State = Scene.state(feet, true)
			state.eyeHeight = STANDING_EYE
			state.lean = SETTINGS.lean

			local eye: vector = Eye.clear(state, world)

			return near("the eye's x", eye.x, face - SETTINGS.clearance)
				or near("the eye's y", eye.y, feet.y + STANDING_EYE + SETTINGS.leanShift.Y)
				or near("the eye's z", eye.z, feet.z)
		end,
	},

	{
		-- Crouched under the ceiling, the eye holds the clearance below its underside
		name = "eyeCeiling",
		run = function (collision: Collision): string?
			local ceiling: Part = Ceiling.ceiling
			local world: World = newWorld(collision)
			local feet: vector = vector.create(ceiling.center.x, RESTING, ceiling.center.z)
			local state: State = Scene.state(feet, true)
			state.posture = "Crouch"
			state.eyeHeight = CROUCHED_EYE

			local eye: vector = Eye.clear(state, world)

			return near("the eye's y", eye.y, Ceiling.underside - SETTINGS.clearance)
				or near("the eye's x", eye.x, feet.x)
				or near("the eye's z", eye.z, feet.z)
		end,
	},

	{
		-- The rules function's speed cap holds the walk under it
		name = "rulesCap",
		run = function (collision: Collision): string?
			local cap: number = 4
			local world: World = newWorld(collision, function (_: RuleStep, _: Allow): number
				return cap
			end)

			local state: State = Scene.state(vector.create(-20, RESTING, -12), true)
			local order: Command = newCommand()
			order.forward = 1
			advance(state, world, order, 1)

			return is("the capped velocity's z", state.velocity.z, -cap)
		end,
	},

	{
		-- The rules function's refusals hold: no jump, no sprint, no crouch, and a crouched body stays crouched
		name = "rulesRefuse",
		run = function (collision: Collision): string?
			local world: World = newWorld(collision, function (_: RuleStep, allow: Allow): number
				allow.jump = false
				allow.sprint = false
				allow.crouch = false
				allow.stand = false

				return math.huge
			end)

			local state: State = Scene.state(vector.create(-20, RESTING, -12), true)
			local order: Command = newCommand()
			order.forward = 1
			order.sprint = true
			order.jump, order.pressed.jump = true, true
			order.crouch, order.pressed.crouch = true, true
			advance(state, world, order, 1)

			local refused: string? = is("grounded", state.grounded, true)
				or is("the jumps", state.jumps, 0)
				or is("the posture", state.posture, "Stand")
				or is("the walk's velocity z", state.velocity.z, -WALK)
				or is("sprint", state.sprint, false)
			if refused then
				return refused
			end

			local crouched: State = Scene.state(vector.create(-20, RESTING, -16), true)
			crouched.posture = "Crouch"
			advance(crouched, world, newCommand(), 1)

			return is("the crouched body's posture", crouched.posture, "Crouch")
		end,
	},

	{
		-- A rules function may allow a jump Tread's physics would not, such as coyote time just after leaving the
		-- ground, and only inside it
		name = "coyoteJump",
		run = function (collision: Collision): string?
			local world: World = newWorld(collision, function (step: RuleStep, allow: Allow): number
				allow.jump = allow.jump or (not step.grounded and step.airTicks <= COYOTE)

				return math.huge
			end)

			local early: State = Scene.state(vector.create(-20, FLOOR + 10, -12), false)
			early.airTicks = 1
			local order: Command = newCommand()
			order.jump, order.pressed.jump = true, true
			advance(early, world, order, 1)

			local jumped: string? = is("the jumps", early.jumps, 1)
				or is("the velocity's y", early.velocity.y, SETTINGS.jump)
			if jumped then
				return jumped
			end

			local late: State = Scene.state(vector.create(-20, FLOOR + 10, -16), false)
			late.airTicks = COYOTE + 1
			local lateOrder: Command = newCommand()
			lateOrder.jump, lateOrder.pressed.jump = true, true
			advance(late, world, lateOrder, 1)

			if late.velocity.y >= 0 then
				return `a jump past the coyote time rose at {late.velocity.y}`
			end

			return is("the jumps past the coyote time", late.jumps, 0)
		end,
	},

	{
		-- The rules function writes its rule-state block, which the state keeps from step to step and a copy carries,
		-- and it is told when it steps an NPC
		name = "ruleBlock",
		run = function (collision: Collision): string?
			local world: World = newWorld(collision, function (step: RuleStep, _: Allow): number
				local block: { [string]: number } = step.block
				block.count += 1
				block.npc = step.isNpc and 1 or 0

				return math.huge
			end)

			local state: State = Scene.state(vector.create(-20, RESTING, -12), true)
			state.block.count = 0
			state.block.npc = 0
			state.npc = true
			advance(state, world, newCommand(), 5)

			local copy: State = State.new()
			State.copy(state, copy)

			return is("the block's count", state.block.count, 5)
				or is("the block's NPC flag", state.block.npc, 1)
				or is("the copy's count", copy.block.count, 5)
		end,
	},

	{
		-- Noclip flies straight through the wall with no gravity and no ground
		name = "noclipWall",
		run = function (collision: Collision): string?
			local world: World = newWorld(collision)
			local start: vector = vector.create(15, RESTING + 2, Geometry.wall.center.z)
			local state: State = Scene.state(start, false)
			state.moveMode = "Noclip"
			local order: Command = newCommand()
			order.forward = 1
			order.yaw = EAST
			advance(state, world, order, 20)

			return near("x", state.position.x, start.x + 20 * WALK * world.delta)
				or near("y", state.position.y, start.y)
				or is("grounded", state.grounded, false)
		end,
	},

	{
		-- Parked holds a body still in the air whatever its command says
		name = "parked",
		run = function (collision: Collision): string?
			local world: World = newWorld(collision)
			local start: vector = vector.create(-20, FLOOR + 10, -12)
			local state: State = Scene.state(start, false)
			state.moveMode = "Parked"
			state.velocity = vector.create(3, -5, 0)
			local order: Command = newCommand()
			order.forward = 1
			order.jump, order.pressed.jump = true, true
			advance(state, world, order, 5)

			local velocity: vector = state.velocity

			return near("x", state.position.x, start.x)
				or near("y", state.position.y, start.y)
				or near("z", state.position.z, start.z)
				or is("the speed", velocity.x * velocity.x + velocity.y * velocity.y + velocity.z * velocity.z, 0)
		end,
	},

	{
		-- Two bodies walking at each other, stepped in slot order, stop a skin apart and never overlap
		name = "bodiesBlock",
		run = function (collision: Collision): string?
			local world: World = newWorld(collision)
			local first: State = Scene.state(vector.create(-26, RESTING, 4), true)
			local second: State = Scene.state(vector.create(-14, RESTING, 4), true)
			World.setBodies(world, { first, second })

			local eastward: Command = newCommand()
			eastward.forward = 1
			eastward.yaw = EAST
			local westward: Command = newCommand()
			westward.forward = 1
			westward.yaw = WEST

			for _ = 1, 12 do
				advance(first, world, eastward, 1)
				advance(second, world, westward, 1)
			end

			local apart: number = second.position.x - first.position.x

			return near("their centers' distance", apart, 2 * RADIUS + SKIN)
				or near("the first's z", first.position.z, 4)
				or near("the second's z", second.position.z, 4)
		end,
	},

	{
		-- A body on another's head slides off it outward at the game's head slide, then drops beside it to the floor
		name = "headSlide",
		run = function (collision: Collision): string?
			local world: World = newWorld(collision)
			local other: State = Scene.state(vector.create(-20, RESTING, 12), true)
			local head: number = RESTING + STANDING + SKIN
			local state: State = Scene.state(vector.create(-19.5, head, 12), true)
			World.setBodies(world, { other, state })

			local order: Command = newCommand()
			advance(state, world, order, 1)

			local slid: string? = near("the first tick's x", state.position.x, -19.5 + SETTINGS.headSlide * world.delta)
				or near("the first tick's y", state.position.y, head)
				or is("grounded on the head", state.grounded, true)
			if slid then
				return slid
			end

			advance(state, world, order, 40)

			if state.position.x - other.position.x < 2 * RADIUS - TOLERANCE then
				return `it ended at x {state.position.x}, still over the other's hull`
			end

			return near("y", state.position.y, RESTING) or is("grounded", state.grounded, true)
		end,
	},

	{
		-- A body inside the wall, which only the exact overlap finds, stays in it on command 9 and leaves it on
		-- command 10, and a body no spot frees is handed back stuck, sunk none
		name = "tenthCommand",
		run = function (collision: Collision): string?
			local wall: Part = Geometry.wall
			local world: World = newWorld(collision)
			local start: vector = vector.create(wall.center.x, RESTING, wall.center.z)
			local state: State = Scene.state(start, true)
			local order: Command = newCommand()

			order.number = 9
			local _: number, ninth: number? = Step.advance(state, order, world)
			local inside: string? = near("the ninth command's x", state.position.x, start.x)
				or is("the ninth command's stuck", ninth, nil)
			if inside then
				return inside
			end

			order.number = 10
			local _: number, tenth: number? = Step.advance(state, order, world)
			local freed: string? = near("the tenth command's x", state.position.x, start.x + 2 * RADIUS)
				or is("the tenth command's stuck", tenth, nil)
			if freed then
				return freed
			end

			local vault: Part = Geometry.vault
			local buried: State = Scene.state(vector.create(vault.center.x, FLOOR + 3, vault.center.z), true)
			local vaultOrder: Command = newCommand()
			vaultOrder.number = 20
			local _: number, stuck: number? = Step.advance(buried, vaultOrder, world)

			return is("the vault's stuck", stuck, 0)
		end,
	},

	{
		-- A move axis past 1, an input that is not finite and a command with no presses are each refused before the
		-- state changes
		name = "refusesInputs",
		run = function (collision: Collision): string?
			local world: World = newWorld(collision)
			local changes: { Change } = {
				{
					label = "a forward of 1.5",
					set = function (order: Command)
						order.forward = 1.5
					end,
					refusal = "forward must be a finite number from -1 to 1",
				},
				{
					label = "a right of -2",
					set = function (order: Command)
						order.right = -2
					end,
					refusal = "right must be a finite number from -1 to 1",
				},
				{
					label = "a forward that is not a number",
					set = function (order: Command)
						order.forward = 0 / 0
					end,
					refusal = "forward must be a finite number",
				},
				{
					label = "an infinite yaw",
					set = function (order: Command)
						order.yaw = math.huge
					end,
					refusal = "yaw must be finite",
				},
				{
					label = "an infinite pitch",
					set = function (order: Command)
						order.pitch = -math.huge
					end,
					refusal = "pitch must be finite",
				},
				{
					label = "a lean that is not a number",
					set = function (order: Command)
						order.lean = 0 / 0
					end,
					refusal = "lean must be finite",
				},
				{
					label = "an infinite head yaw",
					set = function (order: Command)
						order.headYaw = math.huge
					end,
					refusal = "head yaw must be finite",
				},
				{
					label = "a head pitch that is not a number",
					set = function (order: Command)
						order.headPitch = 0 / 0
					end,
					refusal = "head pitch must be finite",
				},
				{
					label = "no presses",
					set = function (order: Command)
						(order :: any).pressed = nil
					end,
					refusal = "needs the presses",
				},
			}

			for _, change: Change in changes do
				local state: State = Scene.state(vector.create(-20, RESTING, -12), true)
				local order: Command = newCommand()
				change.set(order)

				local ran: boolean, message: any = pcall(Step.advance, state, order, world)
				local refusal: string? = refuses(change.label, change.refusal, ran, message)
					or is(`the command number after {change.label}`, state.command, 0)
				if refusal then
					return refusal
				end
			end

			return nil
		end,
	},

	{
		-- A rules function returning anything but a speed cap of 0 or more is refused
		name = "refusesRules",
		run = function (collision: Collision): string?
			local returns: { Return } = {
				{
					label = "a string",
					give = function (): any
						return "fast"
					end,
				},
				{
					label = "nothing",
					give = function (): any
						return nil
					end,
				},
				{
					label = "a number that is not one",
					give = function (): any
						return 0 / 0
					end,
				},
				{
					label = "a negative cap",
					give = function (): any
						return -1
					end,
				},
			}

			for _, row: Return in returns do
				local world: World = newWorld(collision, function (_: RuleStep, _: Allow): number
					return row.give()
				end)

				local state: State = Scene.state(vector.create(-20, RESTING, -12), true)
				local ran: boolean, message: any = pcall(Step.advance, state, newCommand(), world)
				local label: string = `rules returning {row.label}`
				local refusal: string? = refuses(label, "must return a speed cap of 0 or more", ran, message)
				if refusal then
					return refusal
				end
			end

			return nil
		end,
	},

	{
		-- A mode or a move mode the step has no tick for is refused, naming it
		name = "refusesModes",
		run = function (collision: Collision): string?
			local world: World = newWorld(collision)

			local mounted: State = Scene.state(vector.create(-20, RESTING, -12), true)
			mounted.mode = "Mounted" :: any
			local ran: boolean, message: any = pcall(Step.advance, mounted, newCommand(), world)
			local mode: string? = refuses("the Mounted mode", "The step has no mode Mounted", ran, message)
			if mode then
				return mode
			end

			local flying: State = Scene.state(vector.create(-20, RESTING, -12), true)
			flying.moveMode = "Flying" :: any
			ran, message = pcall(Step.advance, flying, newCommand(), world)

			return refuses("the Flying move mode", "The step has no move mode Flying", ran, message)
		end,
	},
}

-- Every trial's name, in the order the live scenario runs them
Ticks.names = {} :: { string }

for _, trial: Trial in TRIALS do
	table.insert(Ticks.names, trial.name)
end

--[[
    Runs one trial by name over a collision, Lune's fixture casts over the
    fixture geometry and its ceiling when none is given, and gives whether
    it ended where it should, with the reason when it did not
--]]

function Ticks.run(name: string, collision: Collision?): (boolean, string | nil)
	for _, trial: Trial in TRIALS do
		if trial.name == name then
			local failure: string? = trial.run(collision or Casts(Ceiling.parts))
			if failure then
				return false, `{name}: {failure}`
			end

			return true, nil
		end
	end

	return false, `no trial is named {name}`
end

return Ticks
