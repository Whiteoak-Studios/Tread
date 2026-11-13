--[[
    Every value the A1 arm runs on: default Humanoid characters under Server
    Authority, with real clients as its only load
--]]

--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Arm.Types)

type Area = Types.Area
type Config = Types.Config

-- The open ground real players stand and walk on
local MAP: Area = { center = Vector3.new(0, 0, 0), size = Vector2.new(2000, 2000) }

local Config: Config = {
	arm = "A1",

	-- Shared by the server and every client: the run's label and steady flag on Workspace, the report's name
	runAttribute = "ArmRun",
	steadyAttribute = "ArmSteady",
	reportName = "ArmReport",
	botsName = "ArmBots",
	floorsName = "ArmFloors",

	warmupSeconds = 30,
	steadySeconds = 120,
	sampleInterval = 1, -- Seconds between Stats samples, on the server and every client
	clientGraceSeconds = 5, -- How long past the steady window a client keeps waiting for the run to end
	percentiles = { 0.5, 0.95, 0.99 },
	fpsPercentile = 0.1, -- G3 reads the server's frame rate at P10

	liveJoinTimeout = 600, -- A live server with no player after this long runs nothing
	liveStartDelay = 60, -- Time for every real device to join before a live program starts
	pauseSeconds = 10, -- Between two runs of a live program
	pollInterval = 0.25,

	-- No group and no viewer: the real players are the whole load, standing in S1 and moving in S2
	program = { "S1", "S2" },
	seeds = { 1, 2, 3 },
	scenarios = {
		S1 = { groups = {} },
		S2 = { groups = {} },
	},
	floors = { MAP },

	rigType = Enum.HumanoidRigType.R15,
	templateTimeout = 30, -- Seconds the default rig's build may take before the run fails
	spawnHeight = 5, -- Bots drop onto the ground from this far up
	moveThreshold = 0.1, -- A Running speed at or below this plays the idle track
	viewerSpacing = 6, -- Studs between real players set down at one viewer point
	floorProbeHeight = 500, -- A floor is laid only where a ray from this high finds no ground
	floorThickness = 2,

	-- What arm-a1.project.json sets on Workspace; keep the two the same. Only AuthorityMode differs
	-- from A0's, so a value read back that differs from this list was set by something other than the file
	settings = {
		{ property = "AuthorityMode", set = Enum.AuthorityMode.Server },
		{ property = "StreamingEnabled", set = true },
		{ property = "NextGenerationReplication", set = Enum.RolloutState.Default },
		{ property = "PlayerScriptsUseInputActionSystem", set = Enum.RolloutState.Default },
		{ property = "SignalBehavior", set = Enum.SignalBehavior.Default },
		{ property = "UseFixedSimulation", set = Enum.RolloutState.Default },
	},
}

return Config
