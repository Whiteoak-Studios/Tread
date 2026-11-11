--[[
    Tread's server settings for the dev game, Frontier Zero's values with
    the fixture's stand-in NPC range, and a round trip for the bots the bot
    harness builds; the dev game adds its pre-command hook where it starts
--]]

--!strict
local Workspace = game:GetService("Workspace")

-- The city block's occluder-only parts, set inside its walls, which the server has from the place's load
local TestContent: Instance? = Workspace:FindFirstChild("TestContent")
local CityBlock: Instance? = TestContent and TestContent:FindFirstChild("CityBlock")
local Occluders: Instance? = CityBlock and CityBlock:FindFirstChild("Occluders")

if not Occluders then
	error("Workspace.TestContent.CityBlock.Occluders is missing, so anti-ESP has no occluders in the dev place")
end

-- A map, since a table that names its keys in another module fits no map type a setting takes
local FOOTSTEP_RANGE: { [string]: number } = { walk = 40, sprint = 60, jump = 60, land = 60 } -- Studs; crouched is silent

-- What anti-ESP's rays may hit, the occluders and solid terrain, typed as the list the setting takes
local OCCLUSION: { Instance } = { Occluders, Workspace.Terrain }

-- Set true on Workspace before the server starts to boot it with the out-of-view rate and records as changes off,
-- since the relay reads both levers only at its start
local LEVERS_OFF_ATTRIBUTE: string = "TreadLeversOff"
local LEVERS_OFF: boolean = Workspace:GetAttribute(LEVERS_OFF_ATTRIBUTE) == true

return {
	rates = {
		move = { perSecond = 35, burst = 60 },
		view = { perSecond = 2, burst = 5 }, -- The render distance a settings menu sends
	},

	catchUp = 2, -- Most ticks one Heartbeat may run after a stall
	slots = { reserve = 296 }, -- 150 players, 96 spawned NPCs and room for 50 bodies
	relevancy = { enter = 950, leave = 1000 },

	tiers = {
		nearEnter = 200,
		nearLeave = 220,
		nearFloor = 15, -- Hz
		nearAim = 20,
		farFloor = 10,
		farAim = 15,
		-- Hz, degrees either side of the look, and studs, left out with the levers off
		outOfView = not LEVERS_OFF and { rate = 5, cone = 70, radius = 40 } or nil,
	},

	relay = { changes = not LEVERS_OFF }, -- Each record as its change since what the viewer last acknowledged
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
		nearRadius = 250, -- Studs from the viewer's eye inside which a hidden pair is rechecked at nearRate
		nearRate = 30,
		visibleRate = 2,
		hold = 1,
		failOpen = 0.15,
		include = OCCLUSION,
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

	npcs = { near = 197, farRate = 2, range = 800 }, -- Frontier Zero sets its NPC draw distance with its NPCs
	history = { seconds = 1 },

	rewind = {
		ceiling = 0.5,
		rttCap = 0.2,
		delayMin = 0.15,
		delayMax = 0.25,
		extra = 2, -- Ticks
		band = 1,
		bandSigmas = 2,
		bandMax = 2,
		rttSmoothing = 1, -- Seconds each connection's round trip and jitter are smoothed over
	},

	teleport = { timeout = 3 },
	bots = { rtt = 0.1 }, -- Seconds a bot's connection reports as its round trip
}
