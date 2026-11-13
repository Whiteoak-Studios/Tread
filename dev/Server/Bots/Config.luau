--[[
    The bot harness's numbers: scenarios S0 to S7 and the gates' loads, the
    seeded runs' timings, the speed calibration and the relevancy sweep, how
    a bot roams, what each cheat sends, and where its floors and spawns go
--]]

--!strict
-- A ground point and the width along X and depth along Z around it, the shape the A0 arm's areas take
export type Area = {
	center: Vector3,
	size: Vector2,
}

-- What a cheater does to what it sends, beside an honest bot's commands
export type Cheat = "lagSwitch" | "relabel" | "tamper" | "crouchLoss" | "freeze" | "longMove"

-- A body Tread's server builds with no player, in place of a bot, its groups after every bot group a scenario has
export type Kind = "npc" | "sleeper"

-- Bodies alike: how many, where each is built, where it walks, and for a bot its faults, cheat, team and spectate
export type Group = {
	name: string, -- What the run's lines call the group
	count: number,
	spawn: Area,
	roam: Area?, -- nil keeps the group standing where it was built
	kind: Kind?, -- nil for bots
	awake: boolean?, -- false idles an NPC group from its build, so it takes no step
	spectate: string?, -- The group whose bots this one's park and spectate, its nth bot built watching their nth
	team: number?, -- Every bot of the group's team, so anti-ESP hides none of them from another
	sprint: boolean?,
	crouch: boolean?,
	lag: { number }?, -- Seconds each bot holds its Moves back, drawn per bot from the first to the second
	loss: { number }?, -- The share of Moves each bot loses, drawn per bot the same way
	cheat: Cheat?,
}

export type Scenario = {
	groups: { Group },
	viewer: Vector3, -- The point the A0 arm puts its real players at
	follow: boolean, -- Whether every area moves so viewer lands on the first real player's character
	storm: boolean, -- Whether the bots all join as the window opens, rather than before the warm-up
	stall: number?, -- Seconds the server is held still for once, half way through the window
}

-- One program of seeded runs
export type Timing = {
	seeds: { number },
	warmup: number, -- Seconds the bots run before the window
	window: number, -- Seconds of the window, its stats read once each interval
	interval: number,
}

-- The fixed workload a run's calibration times, a sample at a time, against a part it lays for the casts
export type Calibration = {
	samples: number, -- Of each workload
	perFrame: number, -- Samples taken between Heartbeats
	bytes: number, -- The buffer each pass of the native loop goes over
	passes: number, -- Passes of the loop a sample times
	casts: number, -- Blockcasts a sample times
	at: Vector3, -- The part's center
	part: Vector3, -- Its size
	block: Vector3, -- Each cast's block
	drop: number, -- Studs above the part's top each block starts, cast down twice as far
}

-- The A0 arm's areas, so B's runs stand their bots where A0's stand
local MAP: Area = { center = Vector3.new(0, 0, 0), size = Vector2.new(2000, 2000) }
local CITY: Area = { center = Vector3.new(3900, 0, 0), size = Vector2.new(600, 600) }
local PLAZA: Area = { center = Vector3.new(3880, 0, -45), size = Vector2.new(100, 60) }
local FIGHT: Area = { center = Vector3.new(0, 0, 0), size = Vector2.new(100, 100) }

-- S9's spread sleepers' square, about 50.5 of them within the 500-stud reveal radius of any map viewer, on the island
local SPREAD: Area = { center = Vector3.new(0, 0, 0), size = Vector2.new(5400, 5400) }

local BOTS: number = 149 -- A 150-slot server's players beside the one real client
local IN_CITY: number = 60 -- S3's bots on the plaza, the rest spread over the map
local CHEATERS: number = 8 -- S7's bots of each cheat, the honest rest roaming beside them
local CHEATS: number = 6 -- S7's cheats, one group each
local NPCS: number = 32 -- Frontier Zero's maxAwake, the most NPCs awake at once
local CITY_SLEEPERS: number = 125 -- The estimate's hotspot, the sleepers one city viewer has within 500 studs
local SPREAD_SLEEPERS: number = 1875 -- The rest of S9's 2,000
local MODERATORS: number = 4 -- S10's spectating moderators, the map group cut by as many
local SCALE: number = 299 -- G10's 300 players beside the one real client
local TEAM: number = 1 -- G5's one team, which every bot and real player shares

local SCENARIOS: { [string]: Scenario } = {
	S0 = { groups = {}, viewer = MAP.center, follow = false, storm = false },

	S1 = {
		groups = { { name = "idle", count = BOTS, spawn = MAP } },
		viewer = MAP.center,
		follow = true,
		storm = false,
	},

	S2 = {
		groups = { { name = "roam", count = BOTS, spawn = MAP, roam = MAP } },
		viewer = MAP.center,
		follow = true,
		storm = false,
	},

	S3 = {
		groups = {
			{ name = "city", count = IN_CITY, spawn = PLAZA, roam = CITY },
			{ name = "map", count = BOTS - IN_CITY, spawn = MAP, roam = MAP },
		},
		viewer = PLAZA.center,
		follow = false,
		storm = false,
	},

	S4 = {
		groups = { { name = "fight", count = BOTS, spawn = FIGHT, roam = FIGHT } },
		viewer = FIGHT.center,
		follow = true,
		storm = false,
	},

	S5 = {
		groups = { { name = "storm", count = BOTS, spawn = MAP, roam = MAP } },
		viewer = MAP.center,
		follow = true,
		storm = true,
	},

	S6 = {
		groups = {
			{ name = "lossy", count = BOTS, spawn = MAP, roam = MAP, lag = { 0, 0.15 }, loss = { 0, 0.05 } },
		},
		viewer = MAP.center,
		follow = true,
		storm = false,
	},

	S7 = {
		groups = {
			-- A lag switch is thrown while sprinting, and a crouched bot stays crouched through its lost packets
			{ name = "lagSwitch", count = CHEATERS, spawn = MAP, roam = MAP, sprint = true, cheat = "lagSwitch" },
			{ name = "relabel", count = CHEATERS, spawn = MAP, roam = MAP, cheat = "relabel" },
			{ name = "tamper", count = CHEATERS, spawn = MAP, roam = MAP, cheat = "tamper" },
			{ name = "crouchLoss", count = CHEATERS, spawn = MAP, roam = MAP, crouch = true, cheat = "crouchLoss" },
			{ name = "freeze", count = CHEATERS, spawn = MAP, roam = MAP, cheat = "freeze" },
			{ name = "longMove", count = CHEATERS, spawn = MAP, roam = MAP, cheat = "longMove" },
			{ name = "honest", count = BOTS - CHEATS * CHEATERS, spawn = MAP, roam = MAP },
		},
		viewer = MAP.center,
		follow = true,
		storm = false,
		stall = 0.5,
	},

	-- G8's load: S3's layout with the city group sprinting, so its bots cross the block's occluders quickly
	G8 = {
		groups = {
			{ name = "city", count = IN_CITY, spawn = PLAZA, roam = CITY, sprint = true },
			{ name = "map", count = BOTS - IN_CITY, spawn = MAP, roam = MAP },
		},
		viewer = PLAZA.center,
		follow = false,
		storm = false,
	},

	-- G3's loads: S3 and S4 with Frontier Zero's awake NPCs beside them, built after the bots so a seed's bots match
	S3Npcs = {
		groups = {
			{ name = "city", count = IN_CITY, spawn = PLAZA, roam = CITY },
			{ name = "map", count = BOTS - IN_CITY, spawn = MAP, roam = MAP },
			{ name = "npcs", kind = "npc", count = NPCS, spawn = PLAZA, roam = CITY },
		},
		viewer = PLAZA.center,
		follow = false,
		storm = false,
	},

	S4Npcs = {
		groups = {
			{ name = "fight", count = BOTS, spawn = FIGHT, roam = FIGHT },
			{ name = "npcs", kind = "npc", count = NPCS, spawn = FIGHT, roam = FIGHT },
		},
		viewer = FIGHT.center,
		follow = true,
		storm = false,
	},

	-- G9's sleepers: S3's layout with 2,000 sleepers lying over the city and spread across the map
	S9 = {
		groups = {
			{ name = "city", count = IN_CITY, spawn = PLAZA, roam = CITY },
			{ name = "map", count = BOTS - IN_CITY, spawn = MAP, roam = MAP },
			{ name = "citySleepers", kind = "sleeper", count = CITY_SLEEPERS, spawn = CITY },
			{ name = "spreadSleepers", kind = "sleeper", count = SPREAD_SLEEPERS, spawn = SPREAD },
		},
		viewer = PLAZA.center,
		follow = false,
		storm = false,
	},

	-- G9's spectate: S3's layout with moderators parked on the plaza, each watching one of the first city bots
	S10 = {
		groups = {
			{ name = "city", count = IN_CITY, spawn = PLAZA, roam = CITY },
			{ name = "map", count = BOTS - IN_CITY - MODERATORS, spawn = MAP, roam = MAP },
			{ name = "moderators", count = MODERATORS, spawn = PLAZA, spectate = "city" },
		},
		viewer = PLAZA.center,
		follow = false,
		storm = false,
	},

	-- G10's 300 players as S2 spreads them, with the awake NPCs, then the same with every NPC idle
	G10 = {
		groups = {
			{ name = "roam", count = SCALE, spawn = MAP, roam = MAP },
			{ name = "npcs", kind = "npc", count = NPCS, spawn = MAP, roam = MAP },
		},
		viewer = MAP.center,
		follow = true,
		storm = false,
	},

	G10Rung2 = {
		groups = {
			{ name = "roam", count = SCALE, spawn = MAP, roam = MAP },
			{ name = "npcs", kind = "npc", count = NPCS, spawn = MAP, roam = MAP, awake = false },
		},
		viewer = MAP.center,
		follow = true,
		storm = false,
	},

	-- G5's load: S4's fight with every bot on one team, so anti-ESP hides none from the real players beside them
	G5 = {
		groups = { { name = "fight", count = BOTS, spawn = FIGHT, roam = FIGHT, team = TEAM } },
		viewer = FIGHT.center,
		follow = true,
		storm = false,
	},
}

return {
	scenarios = SCENARIOS,
	order = { "S0", "S1", "S2", "S3", "S4", "S5", "S6", "S7" }, -- The order the smoke run takes them in

	-- The gates' loads, in the order their smoke run takes them
	gates = { "S3Npcs", "S4Npcs", "S9", "S10", "G10", "G10Rung2", "G5" },

	-- The commands' game fields at rest, by the dev game's own declarations: empty hands and no shot
	fields = { slot = 0, shots = {} } :: { [string]: any },

	-- The benchmark program's runs, and the smoke run's, which shows only that each scenario drives and cleans up
	full = { seeds = { 1, 2, 3 }, warmup = 30, window = 120, interval = 1 } :: Timing,
	smoke = { seeds = { 1 }, warmup = 2, window = 3, interval = 1 } :: Timing,
	percentiles = { 0.5, 0.95, 0.99 },
	fps = 0.1, -- The share the server's frame rate is read at, G3's p10

	tick = {
		-- Each runs once a tick, so their rings of times advance together and sum tick by tick
		stages = { "decode", "simulate", "npcs", "history", "relay" },
		beside = "antiEsp", -- Runs between ticks too, so its p95 prints beside their total and never in it

		-- The stats' counts since the last read that a run also prints a tick, over the ticks each read ran
		counts = { "recordsSent", "recordsCut", "bytesOut", "antiEspTests" },
	},

	-- The fixed workload every run opens with, so its figures scale across servers whose speeds differ
	calibration = {
		samples = 400, -- Of each workload, for its p50 and p95
		perFrame = 8, -- Samples taken between Heartbeats, so the timing never holds the server for long
		bytes = 1024,
		passes = 20,
		casts = 100,
		at = Vector3.new(-5000, 500, 5000), -- Far from every load wherever a run moves it, and from the island
		part = Vector3.new(16, 2, 16),
		block = Vector3.new(2, 2, 2),
		drop = 4,
	} :: Calibration,

	-- S3's city mix and S4's fight at each render distance every viewer is set to, one shortened seed each
	relevancy = {
		scenarios = { "S3", "S4" },
		distances = { 500, 750, 1000 }, -- Studs, the last the dev server's relevancy.leave
		timing = { seeds = { 1 }, warmup = 15, window = 60, interval = 1 } :: Timing,
	},

	stage = "bots", -- The stage every bot sends from, after the relay
	scope = "Tread", -- The Volt scope a bot's client side sends on
	delay = 0.15, -- Seconds of interpolation delay a bot's Move reports, where the dev client's adaptive delay starts

	roam = {
		arrive = 4, -- Studs from its goal at which a bot picks the next one
		patience = 2, -- How many times the straight walk's ticks a bot spends on a goal before it gives up on it
	},

	cheats = {
		every = 5, -- Seconds from one cheat's start to its next
		holds = { 0.25, 0.5, 1, 2 }, -- Seconds a lag switch or a relabeling bot holds its Moves, in turn
		ahead = { 1, 20 }, -- Ticks past its clock a relabeling bot renumbers its held commands, the least and most
		drops = 4, -- Moves a crouched bot loses in a row
		freeze = 2, -- Seconds a frozen client sends nothing
	},

	spawn = {
		batch = 10, -- Bots built a frame, so a run's build never holds the server past the engine's script timeout
		lift = 0.5, -- Studs above the ground a bot is built at
		tries = 10, -- Draws a body's spawn takes at most while its standing hull there meets test content or a body
		probe = 500, -- Studs above an area its ground is cast for from, and as far below
		thickness = 2, -- Of a floor laid where an area has no ground
		tile = 2048, -- The most studs a part spans along an axis, so a wider floor is laid in tiles
		sink = 0.05, -- Studs a floor's top sits below its area's height, under any ground already there
		margin = 20, -- Studs a floor reaches past its area's edge on each side
	},

	moved = 1, -- Studs a roaming group's bots must have moved on average for a run to count it driven

	mirror = {
		offset = 10, -- Studs along X the mirror bot is built from the player's character
		find = 30, -- Seconds the run waits for a real player's character standing still
		settle = 1, -- Seconds after the bot is built before its state is held to the player's
		compare = 20, -- Seconds of ticks compared
	},
}
