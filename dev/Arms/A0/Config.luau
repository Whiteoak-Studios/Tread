--[[
    Every value the A0 arm runs on: default Humanoid characters, 149 or 299 of
    them driven by the server through its scenarios, beside the real clients
--]]

--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Arm.Types)

type Area = Types.Area
type Config = Types.Config

-- The open map every spread group walks, on Roblox's default baseplate or the floor the arm lays
local MAP: Area = { center = Vector3.new(0, 0, 0), size = Vector2.new(2000, 2000) }

-- The city block's footprint and plaza as the dev place holds them, so a copy pasted in here lines up
local CITY: Area = { center = Vector3.new(3900, 0, 0), size = Vector2.new(600, 600) }
local PLAZA: Area = { center = Vector3.new(3880, 0, -45), size = Vector2.new(100, 60) }

-- A 150-player fight packs everyone inside about 100 studs
local FIGHT: Area = { center = Vector3.new(0, 0, 0), size = Vector2.new(100, 100) }

local VIEWER_HEIGHT: number = 5 -- Real players drop onto the ground from this far up
local MAP_VIEWER: Vector3 = MAP.center + Vector3.new(0, VIEWER_HEIGHT, 0)
local CITY_VIEWER: Vector3 = PLAZA.center + Vector3.new(0, VIEWER_HEIGHT, 0)

local Config: Config = {
	arm = "A0",

	-- Shared by the server and every client: the run's label, steady window and program's end on Workspace, the
	-- report's name
	runAttribute = "ArmRun",
	steadyAttribute = "ArmSteady",
	doneAttribute = "ArmDone",
	reportName = "ArmReport",
	botsName = "ArmBots",
	floorsName = "ArmFloors",

	sampleInterval = 1, -- Seconds between Stats samples, on the server and every client
	clientGraceSeconds = 5, -- How long past the steady window a client keeps waiting for the run to end
	percentiles = { 0.5, 0.95, 0.99 },
	fpsPercentile = 0.1, -- G3 reads the server's frame rate at P10

	liveJoinTimeout = 600, -- A live server with no player after this long runs nothing
	pollInterval = 0.25,
	outputWait = 5, -- Seconds after ParallelProbe returns that the rest of its Output may take to reach the report

	program = "quick",
	programs = {
		-- S1 to S4 over three seeds, the whole comparison with B
		full = {
			scenarios = { "S1", "S2", "S3", "S4" },
			seeds = { 1, 2, 3 },
			warmupSeconds = 30,
			steadySeconds = 120,
			startDelay = 60,
			pauseSeconds = 10,
			parallelProbe = false,
		},

		-- The city mix and the fight at 150 and 300 players, one seed each, done within 5 minutes of the first join,
		-- then ParallelProbe on the server with no bots in, as the dev place runs it
		quick = {
			scenarios = { "S3", "S4", "S3x300", "S4x300" },
			seeds = { 1 },
			warmupSeconds = 10,
			steadySeconds = 40,
			startDelay = 10,
			pauseSeconds = 5,
			parallelProbe = true,
		},
	},

	scenarios = {
		S1 = {
			groups = { { count = 149, spawn = MAP } },
			viewer = MAP_VIEWER,
		},

		S2 = {
			groups = { { count = 149, spawn = MAP, roam = MAP } },
			viewer = MAP_VIEWER,
		},

		S3 = {
			groups = {
				{ count = 60, spawn = PLAZA, roam = CITY },
				{ count = 89, spawn = MAP, roam = MAP },
			},
			viewer = CITY_VIEWER,
		},

		S4 = {
			groups = { { count = 149, spawn = FIGHT, roam = FIGHT } },
			viewer = MAP_VIEWER,
		},

		-- S3 and S4 at 300 players, as the bot harness defines them
		S3x300 = {
			groups = {
				{ count = 120, spawn = PLAZA, roam = CITY },
				{ count = 179, spawn = MAP, roam = MAP },
			},
			viewer = CITY_VIEWER,
		},

		S4x300 = {
			groups = { { count = 299, spawn = FIGHT, roam = FIGHT } },
			viewer = MAP_VIEWER,
		},
	},
	floors = { MAP, CITY },

	rigType = Enum.HumanoidRigType.R15,
	templateTimeout = 30, -- Seconds the default rig's build may take before the run fails
	spawnHeight = 5, -- Bots drop onto the ground from this far up
	moveThreshold = 0.1, -- A Running speed at or below this plays the idle track
	viewerSpacing = 6, -- Studs between real players set down at one viewer point
	floorProbeHeight = 500, -- A floor is laid only where a ray from this high finds no ground
	floorThickness = 2,

	panel = {
		key = Enum.KeyCode.L, -- Bound to nothing in Roblox's default controls
		wait = 10,
		size = Vector2.new(760, 400),
		row = 24,
		gap = 6,
		bar = 8,
		textSize = 14,
	},

	-- What arm-a0.project.json sets on Workspace; keep the two the same
	settings = {
		{ property = "AuthorityMode", set = Enum.AuthorityMode.Automatic },
		{ property = "StreamingEnabled", set = true },
		{ property = "NextGenerationReplication", set = Enum.RolloutState.Default },
		{ property = "PlayerScriptsUseInputActionSystem", set = Enum.RolloutState.Default },
		{ property = "SignalBehavior", set = Enum.SignalBehavior.Default },
		{ property = "UseFixedSimulation", set = Enum.RolloutState.Default },
	},
}

return Config
