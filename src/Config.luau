--[[
    Checks the three tables a game starts Tread with, erroring on the first
    key missing or wrong by its full path, and hashes the shared table the
    server's handshake sends, so a client built with another never connects
--]]

--!strict
local Constants = require(script.Parent.Constants)
local Hash = require(script.Parent.Codec.Hash)
local Math = require(script.Parent.Step.Math)

-- The highest eye height or mantle height OwnerState's u8 holds
local EYE_LIMIT: number = (2 ^ Constants.EYE_BITS - 1) * Constants.EYE_QUANTUM
local VELOCITY_LIMIT: number = Constants.VELOCITY_LIMIT
local SLOTS: number = Constants.SLOTS
local TIMER_LIMIT: number = Constants.TIMER_LIMIT -- The most ticks a mantle or a slide's cooldown takes, each a u8
local STRAIGHT_DOWN: number = 90 -- Degrees below level a look points straight down at
local HALF_TURN: number = 180 -- Degrees a view cone's half-angle reaches at most, every direction
local PLAYER_RAYS: number = Constants.PLAYER_RAYS -- The rays anti-ESP's player pair test has
local LYING_RAYS: number = Constants.LYING_RAYS -- A sleeper's or body's

local SHARED_PATH: string = "shared" -- How a refusal names each table's keys
local SERVER_PATH: string = "server"
local CLIENT_PATH: string = "client"

local OPTIONAL: string = "?" -- Ends a spec's key that a game may leave out
local ANY: string = "*" -- A spec's key for every key a game names itself, such as a hit zone or a joint

local COLLISION_FUNCTIONS: { string } = { "ray", "sweep", "rest", "sphere" }

-- The hash's walk writes each value as its tag, then its contents, little-endian
local TAGS: { [string]: number } = { boolean = 1, number = 2, string = 3, Vector3 = 4, Instance = 5, table = 6 }
local END_TAG: number = 7 -- Closes a table's keys and values
local TAG_FORMAT: string = "<B"
local BOOLEAN_FORMAT: string = "<BB" -- 1 or 0
local NUMBER_FORMAT: string = "<Bd" -- The number's exact 8 bytes
local TEXT_FORMAT: string = "<Bs4" -- A u32 length, then the bytes: a string's, or an Instance's full name
local VECTOR_FORMAT: string = "<Bddd" -- Each component's 8 bytes

-- What a refusal says each kind of value a spec names should have been
local EXPECTED: { [string]: string } = {
	number = "a number",
	positive = "a number above 0",
	nonNegative = "a number of 0 or more",
	ratio = "a number from 0 to 1",
	whole = "a whole number of 0 or more",
	count = "a whole number of 1 or more",
	burst = "a number of 1 or more, since each message takes a whole token",
	reserve = `a whole number from 0 to {SLOTS}`,
	speed = `a speed above 0 that rounds to OwnerState's precision below {VELOCITY_LIMIT} studs/s, which its i16 holds`,
	height = `a height above 0 that rounds to OwnerState's precision at most {EYE_LIMIT} studs, which its u8 holds`,
	drop = `a number of degrees above 0 and below {STRAIGHT_DOWN}`,
	cone = `a half-angle in degrees above 0 and at most {HALF_TURN}`,
	lyingRays = `a whole number from 1 to {LYING_RAYS}, the rays a sleeper's or body's test has`,
	boolean = "true or false",
	["function"] = "a function",
	vector = "a Vector3",
	color = "a Color3",
	string = "a string",
	list = "a table",
	instance = "an Instance",
	model = "a Model",
	animation = "an Animation",
}

local RATE: Specs = { perSecond = "positive", burst = "burst" }
local SHAPE: Specs = { from = "vector", to = "vector", radius = "positive" }
local POSTURE: Specs = { body = SHAPE, zones = { [ANY] = SHAPE }, waist = "number" }
local AIM: Specs = { [ANY] = { up = "number", side = "number", ["lead?"] = "boolean" } } -- A list, as checkAim holds it

local SHARED: Specs = {
	rates = { simulation = "positive", relay = "positive" },

	ticks = {
		standIn = "whole",
		ahead = "whole",
		queueWait = "whole",
		leadMin = "whole",
		leadMax = "whole",
		nudge = "ratio",
		resync = "whole",
		debt = "count",
	},

	step = {
		gravity = "positive",
		walk = "speed",
		sprint = "speed",
		crouch = "speed",
		swim = "speed",
		swimSprint = "speed",
		ladder = "speed",
		ladderSprint = "speed",
		jump = "speed",
		stepHeight = "nonNegative",
		walkable = "ratio",
		standable = "ratio",
		terminal = "speed",
		landing = "nonNegative",
		airEase = "positive",
		ladderEase = "positive",
		waterEase = "positive",
		waterEntry = "ratio",
		radius = "positive",
		standing = "positive",
		crouched = "positive",
		eyeStanding = "height",
		eyeCrouched = "height",
		eyeDowned = "height",
		eyeEase = "positive",
		clearance = "positive",
		clearanceStart = "positive",
		lean = "positive",
		leanShift = "vector",
		leanRate = "positive",
		headCone = "positive",
		ladderDrop = "drop",
		swimEnter = "positive",
		swimLeave = "positive",
		floatDepth = "nonNegative",
		crouchDepth = "positive",
		mantleHeight = "height",
		mantleReach = "positive",
		mantleTime = "positive",
		mantleArc = "nonNegative",
		ladderJump = "speed",
		headSlide = "positive",
		lyingBox = { length = "positive", width = "positive", height = "positive", lift = "nonNegative" },

		["slide?"] = {
			start = "speed",
			boost = "nonNegative",
			friction = "nonNegative",
			slope = "ratio",
			max = "speed",
			stop = "speed",
			steer = "nonNegative",
			cooldown = "nonNegative",
		},
	},

	tolerances = {
		Ground = "whole",
		Air = "whole",
		Swim = "whole",
		Ladder = "whole",
		Rider = "whole",
		Mantle = "whole",
	},

	hitShapes = { Stand = POSTURE, Crouch = POSTURE, Downed = POSTURE },

	collision = {
		["ray?"] = "function",
		["sweep?"] = "function",
		["rest?"] = "function",
		["sphere?"] = "function",
		["include?"] = { [ANY] = "instance" },
	},

	["water?"] = "function",
	rules = "function",
	fields = { command = "list", rules = "list", server = "list", slot = "list", held = "list" },
}

local SERVER: Specs = {
	rates = { move = RATE, view = RATE }, -- One per inbound endpoint Schemas/Tread.volt declares, keyed by its name
	catchUp = "count",
	slots = { reserve = "reserve" },
	relevancy = { enter = "positive", leave = "positive" },

	tiers = {
		nearEnter = "positive",
		nearLeave = "positive",
		nearFloor = "positive",
		nearAim = "positive",
		farFloor = "positive",
		farAim = "positive",
		["outOfView?"] = { rate = "positive", cone = "cone", radius = "nonNegative" },
	},

	["relay?"] = { ["changes?"] = "boolean" },
	weights = { near = "positive", far = "positive", shooter = "positive", cone = "positive" },
	shotNear = { rate = "positive", seconds = "positive" },
	budget = { soft = "positive", hard = "positive" },

	antiEsp = {
		aim = { Stand = AIM, Crouch = AIM, Downed = AIM },
		lookAheadMin = "nonNegative",
		lookAheadMax = "nonNegative",
		slice = "positive",
		hiddenRate = "positive",
		nearRadius = "positive",
		nearRate = "positive",
		visibleRate = "positive",
		hold = "nonNegative",
		failOpen = "positive",
		include = { [ANY] = "instance" },
	},

	footsteps = {
		range = { ["walk?"] = "positive", ["sprint?"] = "positive", ["jump?"] = "positive", ["land?"] = "positive" },
		stride = { walk = "positive", sprint = "positive" },
	},

	sleepers = {
		radius = "positive",
		rays = "lyingRays",
		retest = "nonNegative",
		rate = "positive",
		hold = "nonNegative",
	},

	npcs = { near = "nonNegative", farRate = "positive", range = "positive" },
	history = { seconds = "positive" },

	rewind = {
		ceiling = "positive",
		rttCap = "nonNegative",
		delayMin = "nonNegative",
		delayMax = "nonNegative",
		extra = "nonNegative",
		band = "positive",
		bandSigmas = "nonNegative",
		bandMax = "positive",
		rttSmoothing = "positive",
	},

	teleport = { timeout = "positive" },
	beforeCommand = "function",
	["prestream?"] = "function",
	["bots?"] = { rtt = "positive" },
}

local CLIENT: Specs = {
	sample = "function",
	look = "function",
	rig = "model",
	joints = { [ANY] = "string" },

	-- One for each state Tread plays, and any other a game keeps beside them
	animations = {
		idle = "animation",
		walk = "animation",
		sprint = "animation",
		crouchIdle = "animation",
		crouchWalk = "animation",
		jump = "animation",
		fall = "animation",
		land = "animation",
		swimIdle = "animation",
		swim = "animation",
		climb = "animation",
		mantle = "animation",
		downed = "animation",
		crawl = "animation",
		[ANY] = "animation",
	},

	dress = "function",
	undress = "function",
	hold = "function",
	interpolation = { delay = "positive", delayMax = "positive", scaleMin = "positive", scaleMax = "positive" },

	bodies = {
		radius = "nonNegative",
		late = "nonNegative",
		minSeconds = "nonNegative",
		maxSeconds = "positive",
		check = "positive",
		settleSpeed = "nonNegative",
		pushSpeed = "nonNegative",
		pushUpBias = "number",
		jointLimits = { [ANY] = { tilt = "nonNegative", twistLower = "number", twistUpper = "number" } },
	},

	spectate = {
		outline = { fill = "color", fillTransparency = "ratio", outline = "color", outlineTransparency = "ratio" },
	},

	smoothing = { decay = "positive", snap = "nonNegative" },
	drawDistance = { desktop = "positive", console = "positive", phone = "positive", tablet = "positive" },
	lod = { full = "nonNegative", footIk = "nonNegative", aim = "nonNegative" },
	firstPerson = { back = "nonNegative" },
}

local SHARED_PAIRS: { Pair } = {
	{ low = "ticks.leadMin", high = "ticks.leadMax", equal = true },
	{ low = "step.standable", high = "step.walkable", equal = true },
	{ low = "step.crouched", high = "step.standing" },
	{ low = "step.clearance", high = "step.clearanceStart" },
	{ low = "step.swimLeave", high = "step.swimEnter" },
}

local SERVER_PAIRS: { Pair } = {
	{ low = "relevancy.enter", high = "relevancy.leave" },
	{ low = "tiers.nearEnter", high = "tiers.nearLeave" },
	{ low = "tiers.nearFloor", high = "tiers.nearAim", equal = true },
	{ low = "tiers.farFloor", high = "tiers.farAim", equal = true },
	{ low = "budget.soft", high = "budget.hard", equal = true },
	{ low = "antiEsp.lookAheadMin", high = "antiEsp.lookAheadMax", equal = true },
	{ low = "npcs.near", high = "npcs.range", equal = true },
	{ low = "rewind.delayMin", high = "rewind.delayMax", equal = true },
	{ low = "rewind.band", high = "rewind.bandMax", equal = true },
}

local CLIENT_PAIRS: { Pair } = {
	{ low = "interpolation.delay", high = "interpolation.delayMax" },
	{ low = "interpolation.scaleMin", high = "interpolation.scaleMax", equal = true },
	{ low = "bodies.minSeconds", high = "bodies.maxSeconds" },
}

local State = require(script.Parent.Step.State)
local Types = require(script.Parent.Types)

type Character = Types.Character
type Command = State.Command
type Fields = State.Fields
type GameCollision = State.GameCollision
type Rules = State.Rules
type Settings = State.Settings
type Values = State.Values
type Water = State.Water

-- A slot's look and its held item, the game's slot-table and held-item fields by name
type Outfit = Values
type Held = Values

-- A key's spec: the kind of value it takes, or the specs of the table it holds by key
type Spec = string | Specs
type Specs = { [string]: Spec }

-- Two keys of one table, the second of which must be above the first, or at least it where equal is set
type Pair = {
	low: string,
	high: string,
	equal: boolean?,
}

export type Shape = Types.Shape

-- A posture's hit shapes: the body capsule, the zones by name, and the height a lean tilts the upper body about
type PostureShapes = {
	body: Shape,
	zones: { [string]: Shape },
	waist: number,
}

-- One inbound endpoint's rate: what a player may send a second, and the most they may save up
type Rate = {
	perSecond: number,
	burst: number,
}

-- A point an enemy pair's ray aims at, in studs from the target's feet
export type AimPoint = {
	read up: number, -- Straight up
	read side: number, -- Across the line from the viewer's eye to the target, positive to the viewer's right
	read lead: boolean?, -- Cast from the eye moved over the look-ahead to the point moved by the target's velocity
}

-- A posture's aim points in the order their rays are cast. Read only, as Tread only reads them, so a list a game builds
-- in its own module fits whichever of its points lead
export type AimPoints = { read [number]: AimPoint }

-- A ragdoll joint's limits in degrees, its BallSocketConstraint's UpperAngle, TwistLowerAngle and TwistUpperAngle
type JointLimit = {
	tilt: number, -- The cone the joint may tilt in
	twistLower: number, -- The twist about its axis, from lower to upper
	twistUpper: number,
}

-- The table both entry points take, which the server's handshake hashes
export type Shared = {
	rates: { simulation: number, relay: number }, -- Hz

	ticks: {
		standIn: number, -- Ticks a stand-in repeats held inputs
		ahead: number, -- How far ahead a command may run before it is dropped
		queueWait: number, -- The cap on a shot's queue wait in the rewind
		leadMin: number, -- The queue the client's clock holds at the server
		leadMax: number,
		nudge: number, -- The largest share the client's clock is nudged by
		resync: number, -- How far the command clock may drift before it snaps
		debt: number, -- The time debt a frozen client keeps, at least 1 tick
	},

	step: Settings,
	tolerances: { Ground: number, Air: number, Swim: number, Ladder: number, Rider: number, Mantle: number }, -- Quanta
	hitShapes: { Stand: PostureShapes, Crouch: PostureShapes, Downed: PostureShapes },
	collision: GameCollision,
	water: Water?,
	rules: Rules,
	fields: Fields,
}

-- The server entry point's own settings
export type ServerSettings = {
	rates: { move: Rate, view: Rate }, -- One per inbound endpoint Tread's schema declares, keyed by its name
	catchUp: number, -- The most ticks one Heartbeat may run
	slots: { reserve: number }, -- The slots sleepers may never take
	relevancy: { enter: number, leave: number }, -- Studs

	tiers: {
		nearEnter: number, -- Studs
		nearLeave: number,
		nearFloor: number, -- Hz
		nearAim: number,
		farFloor: number,
		farAim: number,

		-- The aim and floor a player outside a viewer's view cone is held to, Hz, the cone's half-angle in degrees,
		-- and the studs inside which no player is held to it; with none, no player is. Tread only reads it, so a
		-- tiers table a game builds in its own module fits with it or without it
		read outOfView: { rate: number, cone: number, radius: number }?,
	},

	-- Whether each record goes as its change since what the viewer last acknowledged; left out or false, whole. Read
	-- only, as tiers.outOfView is, so a game's own relay table fits
	read relay: { read changes: boolean? }?,

	weights: { near: number, far: number, shooter: number, cone: number }, -- The allocator's priorities
	shotNear: { rate: number, seconds: number },
	budget: { soft: number, hard: number }, -- KB/s a viewer gets across every Volt stream

	antiEsp: {
		read aim: { read Stand: AimPoints, read Crouch: AimPoints, read Downed: AimPoints }, -- 1 to PLAYER_RAYS each
		lookAheadMin: number, -- Seconds
		lookAheadMax: number,
		slice: number, -- Seconds it may take a Heartbeat
		hiddenRate: number, -- Hz
		nearRadius: number, -- Studs from the viewer's eye inside which a hidden pair is rechecked at nearRate instead
		nearRate: number, -- Hz
		visibleRate: number,
		hold: number, -- Seconds
		failOpen: number,
		include: { Instance }, -- What its rays may hit, CanCollide on or off: the occluder folder, and Terrain
	},

	footsteps: {
		-- Studs each kind of step is heard at, keyed walk, sprint, jump and land; a kind with none is silent. A map,
		-- since under the new type checker a game's own table naming every kind fits no optional key
		range: { [string]: number },
		stride: { walk: number, sprint: number }, -- Studs a culled enemy covers a step
	},

	sleepers: { radius: number, rays: number, retest: number, rate: number, hold: number },
	npcs: { near: number, farRate: number, range: number },
	history: { seconds: number },

	rewind: {
		ceiling: number, -- Seconds
		rttCap: number,
		delayMin: number,
		delayMax: number,
		extra: number, -- Ticks
		band: number,
		bandSigmas: number,
		bandMax: number,
		rttSmoothing: number, -- Seconds, the time constant each connection's round trip and jitter are smoothed over
	},

	teleport: { timeout: number },

	beforeCommand: (character: Character, command: Command) -> (),
	prestream: ((player: Player, at: CFrame) -> any)?, -- Returns a Promise that resolves once the destination is ready
	bots: { rtt: number }?, -- Seconds a bot's connection reports; only a server that creates bots sets it
}

-- The client entry point's own settings
export type ClientSettings = {
	sample: (command: Command) -> (), -- Fills the command Tread is about to send with this tick's input
	look: () -> (number, number, number, number), -- This frame's base yaw and pitch, radians, and head offset, degrees
	rig: Model, -- The rig template
	joints: { [string]: string }, -- Each logical joint's name in the template
	animations: { [string]: Animation }, -- One for each locomotion state Tread plays, by the state's name
	dress: (rig: Model, outfit: Outfit, copy: boolean) -> (),
	undress: (rig: Model) -> (),
	hold: (rig: Model, held: Held?) -> (),
	interpolation: { delay: number, delayMax: number, scaleMin: number, scaleMax: number },

	bodies: {
		radius: number, -- Studs
		late: number, -- Seconds
		minSeconds: number,
		maxSeconds: number,
		check: number,
		settleSpeed: number, -- Studs/s
		pushSpeed: number,
		pushUpBias: number,
		jointLimits: { [string]: JointLimit }, -- By logical joint
	},

	-- The outline a spectating moderator sees every other player with through walls, transparencies from 0 to 1
	spectate: {
		outline: { fill: Color3, fillTransparency: number, outline: Color3, outlineTransparency: number },
	},

	smoothing: { decay: number, snap: number },
	drawDistance: { desktop: number, console: number, phone: number, tablet: number }, -- Studs
	lod: { full: number, footIk: number, aim: number },
	firstPerson: { back: number }, -- Studs the first-person copy is drawn behind the world rig, along its facing
}

local Config = {}

-- Says what a game gave, as a refusal names it
local function describe(value: any): string
	local kind: string = typeof(value)

	if kind == "string" then
		return `"{value}"`
	elseif kind == "Instance" then
		return `the {value.ClassName} {value:GetFullName()}`
	elseif kind == "number" or kind == "boolean" or kind == "nil" then
		return tostring(value)
	end

	return `a {kind}`
end

-- Errors naming a key by its full path, with what it expected and what the game gave
local function refuse(path: string, expected: string, value: any)
	error(`{path} expected {expected}, and got {describe(value)}`, 0)
end

-- Orders keys numbers first and strings second, each by value, and any other by its text
local function before(a: any, b: any): boolean
	local aType: string, bType: string = type(a), type(b)

	if aType ~= bType then
		return aType < bType
	elseif aType == "number" or aType == "string" then
		return a < b
	end

	return tostring(a) < tostring(b)
end

local function sortedKeys(source: { [any]: any }): { any }
	local keys: { any } = {}

	for key in source do
		table.insert(keys, key)
	end

	table.sort(keys, before)

	return keys
end

-- A key's full path from its table's: a name after a dot, any other key in brackets
local function join(path: string, key: any): string
	if type(key) == "string" then
		return `{path}.{key}`
	end

	return `{path}[{tostring(key)}]`
end

--[[
    Whether a value is of the kind a spec names: a boolean, a function, a
    Vector3, a string, a table, an Instance of a class, or a finite number
    in the kind's range
--]]

local function accepts(kind: string, value: any): boolean
	if kind == "boolean" then
		return type(value) == "boolean"
	elseif kind == "function" then
		return type(value) == "function"
	elseif kind == "vector" then
		return typeof(value) == "Vector3"
	elseif kind == "color" then
		return typeof(value) == "Color3"
	elseif kind == "string" then
		return type(value) == "string"
	elseif kind == "list" then
		return type(value) == "table"
	elseif kind == "instance" then
		return typeof(value) == "Instance"
	elseif kind == "model" then
		return typeof(value) == "Instance" and (value :: Instance):IsA("Model")
	elseif kind == "animation" then
		return typeof(value) == "Instance" and (value :: Instance):IsA("Animation")
	end

	-- Every other kind is a number, and none takes NaN or an infinity
	if type(value) ~= "number" or not (math.abs(value) < math.huge) then
		return false
	end

	if kind == "number" then
		return true
	elseif kind == "positive" then
		return value > 0
	elseif kind == "nonNegative" then
		return value >= 0
	elseif kind == "ratio" then
		return value >= 0 and value <= 1
	elseif kind == "whole" then
		return value >= 0 and value % 1 == 0
	elseif kind == "count" then
		return value >= 1 and value % 1 == 0
	elseif kind == "burst" then
		return value >= 1
	elseif kind == "reserve" then
		return value >= 0 and value <= SLOTS and value % 1 == 0
	elseif kind == "speed" then
		-- The step's quantizers round with no clamp, so each speed must round to a value the wire holds
		return value > 0 and Math.quantizeVelocity(value) < VELOCITY_LIMIT
	elseif kind == "height" then
		return value > 0 and Math.quantizeEye(value) <= EYE_LIMIT
	elseif kind == "drop" then
		return value > 0 and value < STRAIGHT_DOWN
	elseif kind == "cone" then
		return value > 0 and value <= HALF_TURN
	elseif kind == "lyingRays" then
		return value >= 1 and value <= LYING_RAYS and value % 1 == 0
	end

	return false
end

--[[
    Checks a value against its spec, a table key by key in sorted order and
    then every key the spec doesn't name, which takes the spec under ANY or
    is refused as no key Tread reads
--]]

local function walk(spec: Spec, value: any, path: string)
	if type(spec) == "string" then
		local expected: string? = EXPECTED[spec]
		if expected == nil then
			error(`Config's specs name {spec}, which is no kind of value it checks`)
		elseif not accepts(spec, value) then
			refuse(path, expected, value)
		end

		return
	end

	if type(value) ~= "table" then
		refuse(path, "a table", value)
	end

	local named: { [any]: boolean } = {}

	for _, name: string in sortedKeys(spec) do
		if name == ANY then
			continue
		end

		local optional: boolean = name:sub(-1) == OPTIONAL
		local key: string = optional and name:sub(1, -2) or name
		local inner: any = value[key]
		named[key] = true

		if inner ~= nil or not optional then
			walk(spec[name], inner, join(path, key))
		end
	end

	local rest: Spec? = spec[ANY]

	for _, key: any in sortedKeys(value) do
		if named[key] then
			continue
		end

		if rest == nil then
			refuse(join(path, key), "no value, since Tread reads no such key", value[key])
		else
			walk(rest, value[key], join(path, key))
		end
	end
end

-- The value at a dotted path of string keys inside a table
local function lookup(root: any, path: string): any
	local value: any = root

	for _, key: string in path:split(".") do
		value = value[key]
	end

	return value
end

--[[
    Refuses the second key of each pair that isn't above the first, or at
    least it where the pair lets the two be equal
--]]

local function checkPairs(list: { Pair }, root: any, path: string)
	for _, pair: Pair in list do
		local low: number = lookup(root, pair.low)
		local high: number = lookup(root, pair.high)

		if high < low or (high == low and not pair.equal) then
			local relation: string = pair.equal and "at least" or "above"
			refuse(`{path}.{pair.high}`, `a number {relation} {path}.{pair.low}'s {low}`, high)
		end
	end
end

--[[
    Refuses a ragdoll joint whose twist runs backward, its upper limit
    below its lower, naming the upper limit as a pair's refusal does
--]]

local function checkJoints(client: any)
	local limits: any = client.bodies.jointLimits

	for _, joint: any in sortedKeys(limits) do
		local limit: any = limits[joint]
		local path: string = join(`{CLIENT_PATH}.bodies.jointLimits`, joint)

		if limit.twistUpper < limit.twistLower then
			refuse(`{path}.twistUpper`, `a number at least {path}.twistLower's {limit.twistLower}`, limit.twistUpper)
		end
	end
end

--[[
    Refuses a collision table that gives some of the four functions but not
    all, or none of them and no include list for engine casts
--]]

local function checkCollision(collision: any)
	local given: boolean = false

	for _, name: string in COLLISION_FUNCTIONS do
		if collision[name] ~= nil then
			given = true
		end
	end

	for _, name: string in COLLISION_FUNCTIONS do
		if given and collision[name] == nil then
			refuse(`{SHARED_PATH}.collision.{name}`, "a function, since another collision function is given", nil)
		end
	end

	if not given and collision.include == nil then
		refuse(`{SHARED_PATH}.collision.include`, "a list of Instances, since no collision function is given", nil)
	end
end

--[[
    Refuses a mantle time that rounds to no tick at the simulation rate, or
    to more than the mantle's u8 progress counts, rounded as the mantle
    rounds it from the time a tick covers, and a mantle reach whose move to
    the face in one tick would be a speed OwnerState can't hold
--]]

local function checkMantle(shared: any)
	local rate: number = shared.rates.simulation
	local mantleTime: number = shared.step.mantleTime
	local ticks: number = math.round(mantleTime / (1 / rate))

	if ticks < 1 or ticks > TIMER_LIMIT then
		local expected: string =
			`a time that rounds to 1 to {TIMER_LIMIT} ticks at {SHARED_PATH}.rates.simulation's {rate}`
		refuse(`{SHARED_PATH}.step.mantleTime`, expected, mantleTime)
	end

	local reach: number = shared.step.mantleReach
	if Math.quantizeVelocity(reach * rate) >= VELOCITY_LIMIT then
		local expected: string =
			`a reach a tick covers below {VELOCITY_LIMIT} studs/s at {SHARED_PATH}.rates.simulation's {rate}`
		refuse(`{SHARED_PATH}.step.mantleReach`, expected, reach)
	end
end

--[[
    Refuses a crouch slide whose stop speed isn't below its start, whose top
    speed is below its start, or whose cooldown rounds to more ticks than
    its u8 counts, rounded as the step rounds it from the time a tick covers
--]]

local function checkSlide(shared: any)
	local slide: any = shared.step.slide
	if slide == nil then
		return
	end

	local path: string = `{SHARED_PATH}.step.slide`
	if slide.stop >= slide.start then
		refuse(`{path}.stop`, `a number below {path}.start's {slide.start}`, slide.stop)
	elseif slide.max < slide.start then
		refuse(`{path}.max`, `a number at least {path}.start's {slide.start}`, slide.max)
	end

	local rate: number = shared.rates.simulation
	if math.round(slide.cooldown / (1 / rate)) > TIMER_LIMIT then
		local expected: string =
			`a time that rounds to at most {TIMER_LIMIT} ticks at {SHARED_PATH}.rates.simulation's {rate}`
		refuse(`{path}.cooldown`, expected, slide.cooldown)
	end
end

local function checkShared(shared: any)
	walk(SHARED, shared, SHARED_PATH)
	checkCollision(shared.collision)
	checkPairs(SHARED_PAIRS, shared, SHARED_PATH)
	checkMantle(shared)
	checkSlide(shared)
end

--[[
    Refuses a posture's aim points that are no list numbered from 1 with no
    gap, or that hold none or more than the rays a player pair's test has,
    naming the first place that breaks it
--]]

local function checkAim(server: any)
	local aim: any = server.antiEsp.aim

	for _, posture: string in sortedKeys(aim) do
		local points: any = aim[posture]
		local path: string = `{SERVER_PATH}.antiEsp.aim.{posture}`

		for place: number, key: any in sortedKeys(points) do
			if key ~= place then
				refuse(join(path, key), "no value, since a posture's points are a list from 1 with no gap", points[key])
			elseif place > PLAYER_RAYS then
				refuse(join(path, key), `no value, since a player pair's test has {PLAYER_RAYS} rays`, points[key])
			end
		end

		if points[1] == nil then
			refuse(join(path, 1), "a point, since each posture aims at least one ray", nil)
		end
	end
end

--[[
    Checks the shared table and the server settings before the server does
    anything else, erroring on the first key missing or wrong, named by its
    full path with what it expected and what it got
--]]

function Config.server(shared: Shared, server: ServerSettings)
	checkShared(shared)
	walk(SERVER, server, SERVER_PATH)
	checkPairs(SERVER_PAIRS, server, SERVER_PATH)
	checkAim(server)
end

--[[
    Checks the shared table and the client settings before the client does
    anything else, erroring as the server's check does. The crouch slide's
    animation is required only where the shared table gives the slide
--]]

function Config.client(shared: Shared, client: ClientSettings)
	checkShared(shared)
	walk(CLIENT, client, CLIENT_PATH)
	checkPairs(CLIENT_PAIRS, client, CLIENT_PATH)
	checkJoints(client)

	if shared.step.slide ~= nil and client.animations.slide == nil then
		refuse(`{CLIENT_PATH}.animations.slide`, `{EXPECTED.animation}, since {SHARED_PATH}.step.slide is given`, nil)
	end
end

--[[
    Writes a value's bytes for the hash: its tag, then a boolean's byte, a
    number's 8 bytes, a string's or an Instance's full name's length and
    bytes, a Vector3's components, or a table's keys and values in sorted
    key order and the end tag. A function is each realm's own, so a key
    holding one is left out
--]]

local function encode(value: any, path: string, into: { string })
	local kind: string = typeof(value)
	local tag: number? = TAGS[kind]
	if tag == nil then
		error(`Config.hash can't hash {path}, which is a {kind}`, 0)
	end

	if kind == "boolean" then
		table.insert(into, string.pack(BOOLEAN_FORMAT, tag, value and 1 or 0))
	elseif kind == "number" then
		table.insert(into, string.pack(NUMBER_FORMAT, tag, value))
	elseif kind == "string" then
		table.insert(into, string.pack(TEXT_FORMAT, tag, value))
	elseif kind == "Vector3" then
		table.insert(into, string.pack(VECTOR_FORMAT, tag, value.X, value.Y, value.Z))
	elseif kind == "Instance" then
		table.insert(into, string.pack(TEXT_FORMAT, tag, value:GetFullName()))
	else
		table.insert(into, string.pack(TAG_FORMAT, tag))

		for _, key: any in sortedKeys(value) do
			local inner: any = value[key]
			if type(inner) == "function" then
				continue
			elseif type(key) ~= "number" and type(key) ~= "string" then
				error(`Config.hash can't hash a key of {path}, which is a {typeof(key)}`, 0)
			end

			encode(key, path, into)
			encode(inner, join(path, key), into)
		end

		table.insert(into, string.pack(TAG_FORMAT, END_TAG))
	end
end

--[[
    The shared table's hash, which the server sends in its handshake: a
    32-bit FNV-1a over every value in it but its functions, walked in sorted
    key order, so two tables equal in every value hash alike however they
    were built, and a change to any value changes it
--]]

function Config.hash(shared: Shared): number
	local parts: { string } = {}
	encode(shared, SHARED_PATH, parts)

	return Hash.text(table.concat(parts))
end

return Config
