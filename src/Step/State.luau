--[[
    The shared step's types: its state, its command, its casts and its world,
    the game's tables they come from, and the state's constructor and its
    copy in place
--]]

--!strict
--!native

-- The game's declared fields by name, a table its body owns and reuses. Tread never reads them by type, and a game
-- reads its own fields with the types it declared
export type Values = { [string]: any }

-- One declaration of the game's, as the shared table's fields lists give it
export type Field = {
	name: string,
	type: "uint" | "int" | "bool" | "group",
	bits: number?, -- A number's width, at most 32
	min: number?, -- A number's range inside its width
	max: number?,
	count: number?, -- A list of at most this many, its length packed in front
	kind: ("held" | "carried" | "dropped")?, -- Required on a command field
	start: (number | boolean)?, -- A rule-state or server-set field's value when a character is built
	fields: { Field }?, -- A group's own fields
	optional: boolean?, -- A slot-table or held-item field packed behind a presence bit
}

export type Fields = {
	command: { Field }, -- Each Move command's fields
	rules: { Field }, -- The rule-state block
	server: { Field }, -- The server-set block
	slot: { Field }, -- The slot-table fields, a character's look
	held: { Field }, -- The held-item fields
}

export type Mode = "Ground" | "Air" | "Swim" | "Ladder" | "Mantle" | "Slide"
export type Posture = "Stand" | "Crouch" | "Downed"
export type MoveMode = "Walk" | "Noclip" | "Parked"
export type WaterLevel = "Dry" | "Wading" | "Surface" | "Under"

-- The presses a command makes, a button held in it and not in the client's previous one, set beside its levels by
-- whoever hands it to the step
export type Pressed = {
	jump: boolean,
	crouch: boolean,
	sprint: boolean,
	aim: boolean,
}

-- One command, as the step runs it: Tread's own fields at the precisions the Move carries, then the game's
export type Command = {
	number: number, -- Its command number, a u16
	forward: number, -- The move axes, each -1 to 1
	right: number,
	jump: boolean, -- The button levels
	crouch: boolean,
	sprint: boolean,
	aim: boolean,
	pressed: Pressed,
	yaw: number, -- The base look, radians
	pitch: number,
	lean: number, -- Degrees
	headYaw: number, -- The head offset, degrees
	headPitch: number,
	fields: Values, -- The game's declared command fields
}

-- The complete step state: every field OwnerState carries, so a replay starts from exactly the server's state, then
-- what each step writes from its ground probe and what reaches the body from outside OwnerState
export type State = {
	command: number, -- The last command it ran, a u16
	tick: number, -- The simulation tick that command ran on, a u16
	depth: number, -- The server's queue depth when OwnerState left
	position: vector, -- The feet, the hull's bottom center, in world coordinates
	velocity: vector,
	facing: number, -- Radians
	mode: Mode,
	posture: Posture,
	sprint: boolean,
	aim: boolean,
	waterLevel: WaterLevel,
	jumps: number, -- The state word's 2-bit jump counter
	lands: number, -- Its 2-bit land counter
	heavy: boolean, -- Whether its last landing was heavy
	epoch: number, -- The full epoch, a u8, whose low 2 bits the state word carries
	platform: number, -- The ridden platform's id, 0 for none
	moveMode: MoveMode,
	grounded: boolean,
	lean: number, -- Degrees
	eyeHeight: number, -- The eased eye height above the feet
	apex: number, -- The fall apex's height since the last ground, ladder or water contact
	groundHeight: number, -- The feet's height where it last stood on the ground, kept off it, which a mantle counts from
	groundTicks: number, -- Ticks on the ground since it landed
	airTicks: number, -- Ticks off the ground since it left it
	mantleTicks: number, -- The mantle's progress
	slideCooldown: number, -- Ticks left before a crouch slide may start again
	mantleRise: number, -- The mantle's rise, in studs
	ladder: number, -- The ladder being climbed, 0 for none
	fields: Values, -- The game's server-set block
	block: Values, -- The game's rule-state block, which the rules function writes

	-- Written by each step's ground probe before it reads them, so OwnerState never carries them
	groundNormal: vector, -- Zero off the ground
	groundMaterial: Enum.Material,

	-- The slot's held-item fields and whether the body is an NPC, which the handles set
	held: Values,
	npc: boolean,
}

-- A cast's hit on the step's side. One table each Collision reuses, so a caller reads it before its next cast
export type Hit = {
	distance: number, -- Studs along the cast's direction before it met the surface
	position: vector,
	normal: vector,
	material: Enum.Material,
	instance: Instance?,
}

-- The step's casts, every value on vector; sweep and overlap take an axis-aligned box by its center and size
export type Collision = {
	ray: (origin: vector, direction: vector) -> Hit?,
	sweep: (center: vector, size: vector, direction: vector) -> Hit?,
	rest: (center: vector, size: vector) -> number?, -- The highest surface under the box, from its top down
	sphere: (center: vector, radius: number, direction: vector) -> Hit?,
	overlap: (center: vector, size: vector) -> boolean, -- Whether the box is inside any collision geometry
	destroy: () -> (), -- Releases what the casts keep, such as the overlap's probe part
}

-- A hit as a game's own collision functions give it, on Vector3
export type GameHit = {
	distance: number, -- Studs along the cast's direction before it met the surface, as RaycastResult.Distance
	position: Vector3,
	normal: Vector3,
	material: Enum.Material,
	instance: Instance?,
}

-- The shared table's collision key: a game's own four functions, or none of them and the instances engine casts may
-- hit. Beside its own functions, include narrows the overlap probe to those parts, which otherwise tests every part
-- with CanCollide on. Tread only reads each key, so a table of the functions a game builds in its own module fits
export type GameCollision = {
	read ray: ((origin: Vector3, direction: Vector3) -> GameHit?)?,
	read sweep: ((center: Vector3, size: Vector3, direction: Vector3) -> GameHit?)?,
	read rest: ((center: Vector3, size: Vector3) -> number?)?,
	read sphere: ((center: Vector3, radius: number, direction: Vector3) -> GameHit?)?,
	read include: { Instance }?,
}

-- The water surface's height at a point, or nil for none
export type Water = (x: number, z: number) -> number?

-- What the rules function reads, and the rule-state block it may write
export type RuleStep = {
	command: Command,
	pressed: Pressed,
	grounded: boolean,
	mode: Mode,
	posture: Posture,
	airTicks: number,
	groundTicks: number,
	fields: Values, -- The server-set fields
	held: Values, -- The held-item fields
	block: Values, -- The rule-state block
	isNpc: boolean,
}

-- What Tread's own physics permits this step, which the rules function may clear, or set for a jump its rules allow
export type Allow = {
	jump: boolean,
	sprint: boolean,
	crouch: boolean,
	stand: boolean,
	slide: boolean, -- A crouch slide's start, false while the step block gives no slide
}

-- The rules function: returns the speed cap, which the stance speed never passes
export type Rules = (step: RuleStep, allow: Allow) -> number

export type LyingBox = {
	length: number,
	width: number,
	height: number,
	lift: number, -- How far above the ground its center sits
}

-- The crouch slide, which runs only for a game whose step block gives it
export type Slide = {
	start: number, -- The horizontal speed a slide needs to start, studs/s
	boost: number, -- The studs/s it adds at the start, never past the sprint plus the boost
	friction: number, -- The studs/s it loses each second
	slope: number, -- The share of gravity along the ground that speeds it downhill and slows it uphill, 0 to 1
	max: number, -- Its top speed
	stop: number, -- The speed below which it ends, below start
	steer: number, -- Degrees a second its direction turns toward the move input
	cooldown: number, -- Seconds from a slide's end to the next start
}

-- The shared table's step block, every key a game gives
export type Settings = {
	gravity: number, -- Studs/s²
	walk: number, -- The stance speeds, studs/s
	sprint: number,
	crouch: number,
	swim: number,
	swimSprint: number,
	ladder: number,
	ladderSprint: number,
	jump: number, -- A jump's upward speed
	stepHeight: number,
	walkable: number, -- The lowest ground normal Y a body walks on
	standable: number, -- The lowest it stands on without gaining height
	terminal: number, -- The terminal falling speed
	landing: number, -- Seconds in the air before a landing counts
	airEase: number, -- How fast velocity moves toward the target, per second
	ladderEase: number,
	waterEase: number,
	waterEntry: number, -- The share of velocity kept on entering water
	radius: number, -- The hull's half width
	standing: number, -- The hull's heights
	crouched: number,
	eyeStanding: number, -- The eye heights above the feet
	eyeCrouched: number,
	eyeDowned: number,
	eyeEase: number,
	clearance: number, -- The eye's distance from walls and ceilings
	clearanceStart: number, -- How far below the hull's top the clearance cast starts
	lean: number, -- The lean limit, degrees
	leanShift: Vector3, -- The eye's shift at full lean, which the world holds as a vector
	leanRate: number, -- The fastest lean the server accepts
	headCone: number, -- The head offset's cone around facing, degrees
	ladderDrop: number, -- Degrees below level past which a climb loses its up part and a grounded body never mounts
	swimEnter: number,
	swimLeave: number,
	floatDepth: number, -- An idle swimmer's feet below the surface
	crouchDepth: number, -- The depth past which crouch is refused
	mantleHeight: number, -- The mantle's reach above the last ground
	mantleReach: number, -- How far past the hull's front a ledge's face may stand for a mantle
	mantleTime: number,
	mantleArc: number, -- How far the mantle's path arches over the point where its feet clear the top
	ladderJump: number,
	headSlide: number, -- How fast a character slides off another's head
	lyingBox: LyingBox,
	slide: Slide?,
}

-- An oriented box in the step's numbers: its center, its unit axes and its full size along them
export type Box = {
	center: vector,
	right: vector,
	up: vector,
	look: vector,
	size: vector,
}

export type Ladder = {
	id: number, -- What a climber's state names it by, 1 up
	box: Box,
}

-- A moving platform as a game builds it alike on both realms. Its path gives where it stands on a server simulation
-- tick, counted unwrapped from the server's start, and from the tick of its last call for one that moves when called
export type Platform = {
	id: number, -- 1 up to MAX_PLATFORMS, the same on every realm
	boxes: { { center: Vector3, size: Vector3 } }, -- Its collision boxes, each centered in the platform's own space
	path: (tick: number, calledAt: number?) -> Vector3,
	model: Model?, -- The client's copy, which Tread moves each frame
}

-- One of a registered platform's boxes in the step's numbers
export type PlatformBox = {
	center: vector, -- From the platform's position
	half: vector, -- Half its size
}

-- One registered platform: its id and its calls, which the handles read, then what only the step reads
export type PlatformEntry = {
	id: number,
	calledAt: number?, -- The latest call's tick, unwrapped, nil before any
	calledBefore: number?, -- The call before it, which the ticks before the latest run from
	_path: (tick: number, calledAt: number?) -> Vector3,
	_boxes: { PlatformBox },
	_tick: number, -- The unwrapped tick _position stands on, math.huge before any
	_position: vector, -- Where it stands on that tick, on the 1/512 quantum
	_under: Collision, -- The world's casts under the platforms' boxes
	_casts: Collision, -- Those casts wrapped to meet the boxes, which the world holds while it holds a platform
}

-- The uniform grid of hull positions on X and Z a server's world keeps, so a hull test visits only the bodies filed in
-- the cells its bounds touch. Its cells tile a fixed square of buckets, and each body is filed by its place in the list
export type Grid = {
	size: number, -- A cell's side, studs
	bodies: { State }, -- The list it filed, so a new list World.setBodies hands the world is filed at the next read
	count: number, -- The bodies that list holds
	places: { [State]: number }, -- Each body's place in it, from 1
	heads: buffer, -- u16 by bucket: the first place filed in it, 0 for none
	following: buffer, -- u16 by place: the next place in its bucket, 0 at the end
	preceding: buffer, -- u16 by place: the place before it, 0 at the start
	buckets: buffer, -- u16 by place: the bucket it is filed in
	found: { number }, -- The places a test's cells hold, reused by every test
}

-- The read-only context the step reads, which World.new builds
export type World = {
	settings: Settings,
	collision: Collision,
	water: Water?,
	rules: Rules,
	isServer: boolean,
	delta: number, -- Seconds a simulation tick covers
	tick: number, -- The simulation tick being stepped
	leanShift: vector, -- The settings' leanShift, crossed once
	ladders: { Ladder },
	bodies: { State }, -- The live players and NPCs this tick, each body's state where it stands now
	grid: Grid?, -- Where those bodies stand, which the hull tests read; nil walks every body
	platforms: { [number]: PlatformEntry }, -- By id
	clock: number, -- An unwrapped simulation tick within 32,767 of every tick the step runs until it is next set
	gravity: number, -- Studs/s², the latest change's, the settings' own before any
	gravityAt: number?, -- The unwrapped tick the latest change applies from, nil before any
	gravityBefore: number, -- The gravity the ticks before gravityAt step under
}

local State = {}

--[[
    A state with every field set: at rest at the origin, airborne, standing,
    walking, and with empty game blocks the handle fills from the
    declarations' starts
--]]

function State.new(): State
	return {
		command = 0,
		tick = 0,
		depth = 0,
		position = vector.zero,
		velocity = vector.zero,
		facing = 0,
		mode = "Air",
		posture = "Stand",
		sprint = false,
		aim = false,
		waterLevel = "Dry",
		jumps = 0,
		lands = 0,
		heavy = false,
		epoch = 0,
		platform = 0,
		moveMode = "Walk",
		grounded = false,
		lean = 0,
		eyeHeight = 0,
		apex = 0,
		groundHeight = 0,
		groundTicks = 0,
		airTicks = 0,
		mantleTicks = 0,
		slideCooldown = 0,
		mantleRise = 0,
		ladder = 0,
		fields = {},
		block = {},
		groundNormal = vector.zero,
		groundMaterial = Enum.Material.Air,
		held = {},
		npc = false,
	}
end

--[[
    Copies one table of game values into another in place, a nested list
    or group into the table already there, and clears every key from no
    longer holds. Only a nested value into lacks makes a table
--]]

function State.copyValues(from: Values, into: Values)
	for key, value in from do
		local existing = into[key]

		if type(value) == "table" then
			if type(existing) ~= "table" then
				existing = {}
				into[key] = existing
			end

			State.copyValues(value, existing)
		else
			into[key] = value
		end
	end

	for key in into do
		if from[key] == nil then
			into[key] = nil
		end
	end
end

--[[
    Copies every field of one state into another, so a replay or a history
    starts from it, keeping into's own tables for the game's blocks. It
    allocates nothing but a nested list or group into has never held
--]]

function State.copy(from: State, into: State)
	into.command = from.command
	into.tick = from.tick
	into.depth = from.depth
	into.position = from.position
	into.velocity = from.velocity
	into.facing = from.facing
	into.mode = from.mode
	into.posture = from.posture
	into.sprint = from.sprint
	into.aim = from.aim
	into.waterLevel = from.waterLevel
	into.jumps = from.jumps
	into.lands = from.lands
	into.heavy = from.heavy
	into.epoch = from.epoch
	into.platform = from.platform
	into.moveMode = from.moveMode
	into.grounded = from.grounded
	into.lean = from.lean
	into.eyeHeight = from.eyeHeight
	into.apex = from.apex
	into.groundHeight = from.groundHeight
	into.groundTicks = from.groundTicks
	into.airTicks = from.airTicks
	into.mantleTicks = from.mantleTicks
	into.slideCooldown = from.slideCooldown
	into.mantleRise = from.mantleRise
	into.ladder = from.ladder
	into.groundNormal = from.groundNormal
	into.groundMaterial = from.groundMaterial
	into.npc = from.npc

	State.copyValues(from.fields, into.fields)
	State.copyValues(from.block, into.block)
	State.copyValues(from.held, into.held)
end

return State
