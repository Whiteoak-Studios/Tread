--[[
    The dev game's shared table, which both of Tread's entry points take:
    Frontier Zero's numbers and declarations, engine casts over the place's
    test content and terrain, and Frontier Zero's movement rules
--]]

--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Packages = ReplicatedStorage.Packages

local Tread = require(Packages.Tread)

local SIMULATION_RATE: number = 20 -- Hz, which the rules count their timers in ticks of
local SHOTS_PER_COMMAND: number = 4 -- Frontier Zero's Ballistics.shotsPerCommand
local AIM_SPEED: number = 8 -- Studs/s while aiming, Frontier Zero's for an item that sets none
local COYOTE: number = 0.1 -- Seconds after leaving the ground a jump still starts
local CRAWL_SPEED: number = 2 -- Studs/s a downed body crawls at
local JUMP_COOLDOWN: number = 0.5 -- Seconds between jumps, and after a body is built
local LANDING_LOCK: number = 0.1 -- Seconds after landing before a jump
local SHOT_LOCK: number = 0.5 -- Seconds after a shot before a sprint
local FORWARD_ONLY_SPRINT: boolean = true -- Sprint only straight ahead; off, a strafe or a backward move sprints too
local CONTENT_WAIT: number = 10 -- Seconds a client waits at boot for the test content's folder

local COYOTE_TICKS: number = math.round(COYOTE * SIMULATION_RATE)
local JUMP_COOLDOWN_TICKS: number = math.round(JUMP_COOLDOWN * SIMULATION_RATE)
local LANDING_LOCK_TICKS: number = math.round(LANDING_LOCK * SIMULATION_RATE)
local SHOT_LOCK_TICKS: number = math.round(SHOT_LOCK * SIMULATION_RATE)

-- Boot-time wait: a client may run before the folder has replicated, though its parts stream in later
local TestContent = Workspace:WaitForChild("TestContent", CONTENT_WAIT)

assert(TestContent, `Workspace.TestContent did not arrive within {CONTENT_WAIT} s`)

--[[
    Frontier Zero's movement rules, run inside Tread's step on the server
    and in the owner's prediction: the jump pacing, sprint forward only
    while the flag holds, its post-shot lock, the aim speed, and the downed
    crawl, which stops while someone revives the body. They allocate
    nothing and never yield
--]]

local function rules(step: Tread.RuleStep, allow: Tread.Allow): number
	local command: Tread.Command = step.command
	local block: { [string]: number } = step.block
	local shots: { any }? = command.fields.shots -- An NPC's command may carry none

	-- Count both timers up to their locks; a shot starts its lock again
	if block.sinceJump < JUMP_COOLDOWN_TICKS then
		block.sinceJump += 1
	end

	if block.sinceShot < SHOT_LOCK_TICKS then
		block.sinceShot += 1
	end

	if shots and #shots > 0 then
		block.sinceShot = 0
	end

	-- A downed body only crawls, and not at all while someone revives it
	if step.posture == "Downed" then
		allow.jump = false
		allow.sprint = false
		allow.crouch = false
		allow.stand = false

		if step.fields.beingRevived then
			return 0
		end

		return CRAWL_SPEED
	end

	-- Jump pacing: a cooldown between jumps, coyote time just after
	-- leaving the ground, and a lock just after landing
	local landed: boolean = not step.grounded or step.groundTicks >= LANDING_LOCK_TICKS
	local coyote: boolean = not step.grounded and step.airTicks <= COYOTE_TICKS
	allow.jump = ((allow.jump and landed) or coyote) and block.sinceJump >= JUMP_COOLDOWN_TICKS

	if allow.jump and step.pressed.jump then
		block.sinceJump = 0
	end

	-- Forward only while the flag holds, never while aiming and never inside the post-shot lock
	local heading: boolean = not FORWARD_ONLY_SPRINT or (command.forward > 0 and command.right == 0)
	allow.sprint = allow.sprint and heading and not command.aim and block.sinceShot >= SHOT_LOCK_TICKS

	if command.aim then
		return AIM_SPEED
	end

	return math.huge
end

local Shared: Tread.Shared = {
	rates = {
		simulation = SIMULATION_RATE,
		relay = 20,
	},

	ticks = {
		standIn = 2, -- Ticks a stand-in repeats held inputs for
		ahead = 5, -- A command further ahead than this is dropped
		queueWait = 3, -- Most queue wait a shot's rewind counts
		leadMin = 1,
		leadMax = 3,
		nudge = 0.02, -- Largest share the client's clock is nudged by
		resync = 3,
		debt = 8,
	},

	step = {
		gravity = 68.1, -- Studs/s², the same as Workspace.Gravity
		terminal = 138.9,
		walk = 10,
		sprint = 18,
		crouch = 6,
		swim = 3.04,
		swimSprint = 6.09,
		ladder = 3.04,
		ladderSprint = 6.09,
		jump = 25, -- Upward speed a jump starts with
		stepHeight = 0.69,
		walkable = 0.643, -- Lowest ground normal Y that's walkable, 50°
		standable = 0.5, -- Stood on with no height gained, to 60°
		landing = 0.3, -- Seconds in the air before a landing counts
		airEase = 3, -- How fast velocity moves toward the target, per second
		ladderEase = 20,
		waterEase = 5,
		waterEntry = 0.1, -- Share of velocity kept on entering water
		radius = 1.39,
		standing = 5,
		crouched = 3.06,
		eyeStanding = 4.17,
		eyeCrouched = 2.5,
		eyeDowned = 0.97,
		eyeEase = 10,
		clearance = 1.45, -- Eye's distance from walls and ceilings
		clearanceStart = 1.5, -- How far below the hull's top the clearance cast starts
		lean = 20, -- Degrees either side
		leanShift = Vector3.new(0.57, -0.1, 0), -- Eye's shift at full lean
		leanRate = 200, -- Degrees a second, the fastest lean the server accepts
		headCone = 75, -- Degrees either side of facing
		ladderDrop = 30, -- Degrees below level a climber's look may point before a climb loses its up part
		swimEnter = 3.25,
		swimLeave = 2.71,
		floatDepth = 1.83, -- An idle swimmer's feet below the surface
		crouchDepth = 2.22,
		mantleHeight = 4,
		mantleReach = 1.39, -- Studs past the hull's front a ledge's face may stand, the hull's radius
		mantleTime = 0.5,
		mantleArc = 0.5, -- Studs the mantle's path arches over the top before it settles onto it
		ladderJump = 25,
		headSlide = 1, -- Studs/s a body slides off another's head
		lyingBox = { length = 5, width = 2, height = 2, lift = 1 },

		-- The crouch slide, which Frontier Zero gives none of
		slide = {
			start = 15, -- Studs/s a slide needs to start, so only a sprint starts one
			boost = 0,
			friction = 6, -- Studs/s it loses each second
			slope = 0.5, -- Share of gravity along the ground
			max = 27,
			stop = 6, -- Studs/s below which it ends
			steer = 60, -- Degrees a second
			cooldown = 2, -- Seconds from its end to the next start
		},
	},

	-- Quanta of 1/512 stud a prediction may drift before the owner replays
	tolerances = {
		Ground = 2,
		Air = 2,
		Swim = 2,
		Ladder = 2,
		Rider = 2,
		Mantle = 0,
	},

	-- Each posture's capsules in the character's own space, and the height a lean tilts the upper body about
	hitShapes = {
		Stand = {
			body = { from = Vector3.new(0, 1, 0), to = Vector3.new(0, 4, 0), radius = 1.4 },
			zones = {
				head = { from = Vector3.new(0, 4.3, 0), to = Vector3.new(0, 4.7, 0), radius = 0.5 },
				chest = { from = Vector3.new(0, 2.9, 0), to = Vector3.new(0, 3.9, 0), radius = 0.9 },
				legs = { from = Vector3.new(0, 0.4, 0), to = Vector3.new(0, 2, 0), radius = 0.7 },
			},
			waist = 2.5,
		},

		Crouch = {
			body = { from = Vector3.new(0, 0.9, 0), to = Vector3.new(0, 2.3, 0), radius = 1.3 },
			zones = {
				head = { from = Vector3.new(0, 2.6, 0), to = Vector3.new(0, 2.9, 0), radius = 0.5 },
				chest = { from = Vector3.new(0, 1.7, 0), to = Vector3.new(0, 2.4, 0), radius = 0.9 },
				legs = { from = Vector3.new(0, 0.4, 0), to = Vector3.new(0, 1.5, 0), radius = 0.7 },
			},
			waist = 1.5,
		},

		Downed = {
			body = { from = Vector3.new(0, 0.6, 1.6), to = Vector3.new(0, 0.6, -1.6), radius = 0.8 },
			zones = {
				head = { from = Vector3.new(0, 0.6, -2.2), to = Vector3.new(0, 0.6, -2.5), radius = 0.5 },
				chest = { from = Vector3.new(0, 0.6, -0.6), to = Vector3.new(0, 0.6, -1.6), radius = 0.8 },
				legs = { from = Vector3.new(0, 0.6, 0.4), to = Vector3.new(0, 0.6, 2.2), radius = 0.6 },
			},
			waist = 0.6,
		},
	},

	-- Engine casts over the place's own geometry, so prediction and the server cast against the same parts
	collision = {
		include = { TestContent, Workspace.Terrain },
	},

	rules = rules,

	fields = {
		command = {
			-- Hotbar slot in hand, 0 for empty hands
			{ name = "slot", kind = "held", type = "uint", bits = 3, max = 6 },

			{
				name = "shots",
				kind = "dropped",
				type = "group",
				count = SHOTS_PER_COMMAND,
				fields = {
					{ name = "sequence", type = "uint", bits = 6 },
					{ name = "class", type = "uint", bits = 2 }, -- Keyboard and mouse, gamepad or touch
					{ name = "renderTick", type = "uint", bits = 16 },
					{ name = "fraction", type = "uint", bits = 8 },
					{ name = "yaw", type = "uint", bits = 16 },
					{ name = "pitch", type = "int", bits = 16 },
				},
			},
		},

		rules = {
			{ name = "sinceJump", type = "uint", bits = 4, start = 0 }, -- A new character starts inside the cooldown
			{ name = "sinceShot", type = "uint", bits = 4, start = 15 },
		},

		server = {
			{ name = "beingRevived", type = "bool", start = false },
		},

		slot = {
			{ name = "head", type = "uint", bits = 16, optional = true },
			{ name = "torso", type = "uint", bits = 16, optional = true },
			{ name = "leg", type = "uint", bits = 16, optional = true },
			{ name = "face", type = "uint", bits = 16, optional = true },
			{ name = "shirt", type = "uint", bits = 16, optional = true },
			{ name = "pants", type = "uint", bits = 16, optional = true },
		},

		held = {
			{ name = "item", type = "uint", bits = 16, optional = true },
			{ name = "skin", type = "uint", bits = 16, optional = true },
		},
	},
}

return Shared
