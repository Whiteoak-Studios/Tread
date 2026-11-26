--[[
    Tread's server settings for the dev game: Frontier Zero's values but the
    dev place's own bands and frame caps, the fixture's stand-in NPC range and
    a round trip for the bots; the dev game adds its pre-command hook at start
--]]

--!strict
local Workspace = game:GetService("Workspace")

-- The city block's and the monuments' occluder-only parts, set inside their walls, which the server has from the
-- place's load
local TestContent: Instance? = Workspace:FindFirstChild("TestContent")
local CityBlock: Instance? = TestContent and TestContent:FindFirstChild("CityBlock")
local Occluders: Instance? = CityBlock and CityBlock:FindFirstChild("Occluders")
local Monuments: Instance? = TestContent and TestContent:FindFirstChild("Monuments")
local MonumentOccluders: Instance? = Monuments and Monuments:FindFirstChild("Occluders")

if not Occluders then
	error("Workspace.TestContent.CityBlock.Occluders is missing, so anti-ESP has no occluders in the dev place")
end

if not MonumentOccluders then
	error("Workspace.TestContent.Monuments.Occluders is missing, so anti-ESP has no occluders for the monuments")
end

-- A map, since a table that names its keys in another module fits no map type a setting takes
local FOOTSTEP_RANGE: { [string]: number } = { walk = 40, sprint = 60, jump = 60, land = 60 } -- Studs; crouched is silent

-- What anti-ESP's rays may hit, the occluders and solid terrain, typed as the list the setting takes
local OCCLUSION: { Instance } = { Occluders, MonumentOccluders, Workspace.Terrain }

-- Set true on Workspace before the server starts to boot it with the out-of-view rate, records as changes, the
-- past a reveal carries and the owner's checks off, since the server reads all four levers at its start
local LEVERS_OFF_ATTRIBUTE: string = "TreadLeversOff"
local LEVERS_OFF: boolean = Workspace:GetAttribute(LEVERS_OFF_ATTRIBUTE) == true

-- Set on Workspace before the server starts to a whole number to boot the relay with that many Actor workers, left out
-- or 0 for none, since the relay makes its workers only at its start
local WORKERS_ATTRIBUTE: string = "TreadRelayWorkers"
local WORKERS: any = Workspace:GetAttribute(WORKERS_ATTRIBUTE) or 0
local RELAY_TIMEOUT: number = 1 -- Seconds a round out on the workers may take before the relay gives it up
local RELAY_BUDGET: number = 0.005 -- Seconds of the server's own script a relay run may take before the rest wait

if type(WORKERS) ~= "number" or WORKERS < 0 or WORKERS % 1 ~= 0 then
	error(`Workspace's {WORKERS_ATTRIBUTE} takes a whole number of relay workers from 0, not {WORKERS}`)
end

-- Set true on Workspace before the server starts to boot the relay with its clocks on, which stats then reads, since
-- the relay reads it only at its start
local CLOCKS_ATTRIBUTE: string = "TreadRelayClocks"
local CLOCKS: boolean = Workspace:GetAttribute(CLOCKS_ATTRIBUTE) == true

-- Set true on Workspace before the server starts to boot the relay with its split by stage on. The dev server watches
-- it after its start too, so a change while it runs reaches the tick loop
local SPLIT_ATTRIBUTE: string = "TreadRelaySplit"
local SPLIT: boolean = Workspace:GetAttribute(SPLIT_ATTRIBUTE) == true

-- Records as changes and the relay's budget, with workers their count and the timeout they need, the clocks and the
-- split while on and a reveal's past while records go as changes, each left out while off
local RELAY: {
	changes: boolean,
	budget: number,
	workers: number?,
	timeout: number?,
	clocks: boolean?,
	split: boolean?,
	past: boolean?,
} =
	{ changes = not LEVERS_OFF, budget = RELAY_BUDGET }
if WORKERS > 0 then
	RELAY.workers = WORKERS
	RELAY.timeout = RELAY_TIMEOUT
end

if CLOCKS then
	RELAY.clocks = true
end

if SPLIT then
	RELAY.split = true
end

if not LEVERS_OFF then
	RELAY.past = true
end

-- Set on Workspace before the server starts to a whole number to boot anti-ESP with that many Actor workers to cast
-- its rays on, left out or 0 for none, since anti-ESP makes its workers only at its start
local ANTI_ESP_ATTRIBUTE: string = "TreadAntiEspWorkers"
local ANTI_ESP_WORKERS: any = Workspace:GetAttribute(ANTI_ESP_ATTRIBUTE) or 0

if type(ANTI_ESP_WORKERS) ~= "number" or ANTI_ESP_WORKERS < 0 or ANTI_ESP_WORKERS % 1 ~= 0 then
	error(`Workspace's {ANTI_ESP_ATTRIBUTE} takes a whole number of anti-ESP workers from 0, not {ANTI_ESP_WORKERS}`)
end

return {
	rates = {
		move = { perSecond = 35, burst = 60 },
		view = { perSecond = 2, burst = 5 }, -- The render distance a settings menu sends
	},

	catchUp = 2, -- Most ticks one Heartbeat may run after a stall
	slots = { reserve = 296 }, -- 150 players, 96 spawned NPCs and room for 50 bodies
	relevancy = { enter = 950, leave = 1000 },

	tiers = {
		bands = { { aim = 20, floor = 15 }, { aim = 10, floor = 10 }, { aim = 5, floor = 5 } }, -- Hz, nearest first
		edges = { { enter = 350, leave = 385 }, { enter = 600, leave = 660 } }, -- Studs
		-- Hz, degrees either side of the look, and studs, left out with the levers off
		outOfView = not LEVERS_OFF and { rate = 5, cone = 70, radius = 40 } or nil,
		crowd = { size = 32, rate = 20, floor = 5 }, -- Players at their band's rates, then the rest's most and least, Hz
		-- The farthest band's rates halved after 20 relay runs in a row over relay.budget, and back after 20 under it
		underLoad = { runs = 20, scale = 0.5 },
	},

	relay = RELAY, -- Records as changes since what the viewer last acknowledged, the budget, workers, clocks, split, past
	owner = { checks = not LEVERS_OFF }, -- A player whose check agrees gets an acknowledgment for its OwnerState
	weights = { near = 1, far = 0.5, shooter = 2, cone = 1.5 },
	shotNear = { rate = 10, seconds = 5 },
	budget = { soft = 64, hard = 96 }, -- KB/s a viewer gets across every Volt stream

	antiEsp = {
		-- Studs above the feet and across the line from the viewer, for the DevRig in its 5-stud hull; the torso's
		-- ray leads with both bodies' movement
		aim = {
			Stand = {
				{ up = 5, side = 0 }, -- The head's top
				{ up = 4, side = -1.4 }, -- The shoulders
				{ up = 4, side = 1.4 },
				{ up = 3, side = 0, lead = true }, -- The torso's center
				{ up = 1, side = -0.5 }, -- The lower legs
				{ up = 1, side = 0.5 },
			},
			Crouch = {
				{ up = 3, side = 0 },
				{ up = 2.4, side = -1.4 },
				{ up = 2.4, side = 1.4 },
				{ up = 1.9, side = 0, lead = true },
				{ up = 0.6, side = -0.5 },
				{ up = 0.6, side = 0.5 },
			},
			Downed = {
				{ up = 1.2, side = 0 },
				{ up = 0.8, side = -1.4 },
				{ up = 0.8, side = 1.4 },
				{ up = 0.6, side = 0, lead = true },
				{ up = 0.4, side = -0.5 },
				{ up = 0.4, side = 0.5 },
			},
		},
		lookAheadMin = 0.15,
		lookAheadMax = 0.45,
		slice = 0.002, -- Seconds anti-ESP may take a Heartbeat
		hiddenRate = 10,
		nearRadius = 250, -- Studs from the viewer's eye inside which a hidden pair is rechecked once every server tick
		visibleRate = 2,
		hold = 1,
		failOpen = 0.15,
		lyingShare = 0.0005, -- Seconds of each slice kept for sleeper and body pairs while any wait
		include = OCCLUSION,
		workers = ANTI_ESP_WORKERS > 0 and ANTI_ESP_WORKERS or nil, -- Actor workers its rays are cast on, left out while 0
		whole = true, -- The slice's timers, walks and queue drains stop at its deadline as its tests do
	},

	footsteps = {
		range = FOOTSTEP_RANGE,
		stride = { walk = 4.5, sprint = 6 }, -- Studs a culled enemy covers a step
	},

	sleepers = {
		radius = 500,
		rays = 3,
		retest = 4, -- Studs a viewer moves before a pair is tested again
		rate = 1.5,
		hold = 2,
	},

	-- Studs, Hz and studs, Frontier Zero setting its NPC draw distance with its NPCs, and the seconds a tick's NPC
	-- steps may take before the rest wait a tick
	npcs = { near = 197, farRate = 2, range = 800, budget = 0.001 },
	history = { seconds = 1 },

	rewind = {
		ceiling = 0.5,
		rttCap = 0.2,
		delayMin = 0.10,
		delayMax = 0.25,
		extra = 2, -- Ticks
		band = 1,
		bandSigmas = 2,
		bandMax = 2,
		rttSmoothing = 1, -- Seconds each connection's round trip and jitter are smoothed over
	},

	teleport = { timeout = 3 },
	-- Seconds a bot's connection reports as its round trip, and every bot taken as agreeing, since none predicts
	bots = { rtt = 0.1, agree = true },
}
