--[[
    An arm's load: server-driven bots cloned from Roblox's own default rig,
    walking with MoveTo while its idle and walk animations play, and the
    floors and viewer points each scenario stands them on
--]]

--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Arm.Config)

local BOTS_NAME: string = Config.botsName
local FLOORS_NAME: string = Config.floorsName
local RIG_TYPE: Enum.HumanoidRigType = Config.rigType
local TEMPLATE_TIMEOUT: number = Config.templateTimeout
local POLL_INTERVAL: number = Config.pollInterval
local SPAWN_HEIGHT: number = Config.spawnHeight
local MOVE_THRESHOLD: number = Config.moveThreshold
local VIEWER_SPACING: number = Config.viewerSpacing
local FLOOR_PROBE_HEIGHT: number = Config.floorProbeHeight
local FLOOR_THICKNESS: number = Config.floorThickness
local SEED_BOUND: number = 2 ^ 31 - 1 -- The largest seed a bot's own path generator takes

local Types = require(ReplicatedStorage.Arm.Types)

type Area = Types.Area
type Group = Types.Group
type Scenario = Types.Scenario

local Template: Model? = nil -- Roblox's default rig, built once a server and cloned for every bot

local Bots = {}

--[[
    A random ground point inside an area
--]]

local function pointIn(area: Area, random: Random): Vector3
	local halfWidth: number = area.size.X / 2
	local halfDepth: number = area.size.Y / 2
	local x: number = random:NextNumber(-halfWidth, halfWidth)
	local z: number = random:NextNumber(-halfDepth, halfDepth)

	return area.center + Vector3.new(x, 0, z)
end

--[[
    Roblox's default rig from a blank HumanoidDescription, built on first
    use. The build waits on Roblox's avatar service, so it runs in its own
    thread and fails the run once its timeout passes
--]]

local function buildTemplate(): Model
	if Template then
		return Template
	end

	local built: Model? = nil
	local failure: string? = nil

	task.spawn(function ()
		local ok: boolean, result: any = pcall(function (): Model
			local description: HumanoidDescription = Instance.new("HumanoidDescription")
			return Players:CreateHumanoidModelFromDescriptionAsync(description, RIG_TYPE)
		end)

		if ok then
			built = result
		else
			failure = tostring(result)
		end
	end)

	local deadline: number = os.clock() + TEMPLATE_TIMEOUT
	while not built and not failure and os.clock() < deadline do
		task.wait(POLL_INTERVAL)
	end

	if failure then
		error(`Roblox's default rig could not be built: {failure}`)
	end

	if not built then
		error(`Roblox's default rig was not built within {TEMPLATE_TIMEOUT} s`)
	end

	Template = built
	return built
end

--[[
    A bot's Humanoid and Animator, and the idle and walk Animations its
    default Animate script carries, erroring when any is missing
--]]

local function rigOf(bot: Model): (Humanoid, Animator, Animation, Animation)
	local humanoid: Humanoid? = bot:FindFirstChildOfClass("Humanoid")
	local animator: Animator? = humanoid and humanoid:FindFirstChildOfClass("Animator")
	local animate: Instance? = bot:FindFirstChild("Animate")
	local idle: Instance? = animate and animate:FindFirstChild("idle")
	local walk: Instance? = animate and animate:FindFirstChild("walk")
	local idleAnimation: Animation? = idle and idle:FindFirstChildOfClass("Animation")
	local walkAnimation: Animation? = walk and walk:FindFirstChildOfClass("Animation")

	if not humanoid or not animator or not idleAnimation or not walkAnimation then
		error("Roblox's default rig lacks its Humanoid, its Animator, or the idle and walk Animations of its Animate")
	end

	return humanoid, animator, idleAnimation, walkAnimation
end

--[[
    Clones one bot into the run's folder at a random point of its group's
    spawn area, owned by the server, playing idle until it moves and then
    walk, and when the group roams walking from one random point to the next
--]]

local function spawnBot(template: Model, name: string, group: Group, folder: Folder, random: Random)
	local bot: Model = template:Clone()
	bot.Name = name
	bot:PivotTo(CFrame.new(pointIn(group.spawn, random) + Vector3.new(0, SPAWN_HEIGHT, 0)))
	bot.Parent = folder

	local humanoid: Humanoid, animator: Animator, idleAnimation: Animation, walkAnimation: Animation = rigOf(bot)

	-- The server drives every bot, so no nearby client takes over its physics
	local root: BasePart? = bot.PrimaryPart
	if root then
		root:SetNetworkOwner(nil)
	end

	-- Whiteoak TODO: bots play only the default rig's idle and walk tracks; once a scenario leaves flat
	-- ground, a server port of the Animate script's run blend, jump and fall replaces this pair
	local idle: AnimationTrack = animator:LoadAnimation(idleAnimation)
	local walk: AnimationTrack = animator:LoadAnimation(walkAnimation)
	idle:Play()

	-- Both connections belong to the bot's Humanoid, so the bot's Destroy() disconnects them
	humanoid.Running:Connect(function (speed: number)
		if speed > MOVE_THRESHOLD then
			if not walk.IsPlaying then
				idle:Stop()
				walk:Play()
			end
		elseif not idle.IsPlaying then
			walk:Stop()
			idle:Play()
		end
	end)

	local roam: Area? = group.roam
	if not roam then
		return
	end

	local area: Area = roam
	local path: Random = Random.new(random:NextInteger(1, SEED_BOUND))

	humanoid.MoveToFinished:Connect(function ()
		humanoid:MoveTo(pointIn(area, path))
	end)

	humanoid:MoveTo(pointIn(area, path))
end

--[[
    Spawns every group of a scenario in order from one seeded generator, so
    a seed puts each bot at the same start and gives it the same path
--]]

local function spawnAll(scenario: Scenario, seed: number, folder: Folder)
	if #scenario.groups == 0 then
		return
	end

	local template: Model = buildTemplate()
	local random: Random = Random.new(seed)
	local count: number = 0

	for _, group: Group in scenario.groups do
		for _ = 1, group.count do
			count += 1
			spawnBot(template, `Bot{count}`, group, folder, random)
		end
	end
end

--[[
    Sets each real player's character down at the scenario's viewer point,
    a few studs apart, so every run measures its clients from the same spot
--]]

local function placeViewers(viewer: Vector3)
	for index: number, player: Player in Players:GetPlayers() do
		local character: Model? = player.Character
		if character then
			local offset: Vector3 = Vector3.new(index * VIEWER_SPACING, 0, 0)
			character:PivotTo(CFrame.new(viewer + offset))
		end
	end
end

--[[
    Lays an anchored floor under each configured area whose center has no
    ground below it, so every scenario runs on a bare place as on one that
    holds Roblox's baseplate or a copy of the city block
--]]

function Bots.layFloors()
	local folder: Folder = Instance.new("Folder")
	folder.Name = FLOORS_NAME
	folder.Parent = Workspace

	local depth: number = FLOOR_PROBE_HEIGHT * 2 -- As far below the area's center as the ray starts above it

	for index: number, area: Area in Config.floors do
		local origin: Vector3 = area.center + Vector3.new(0, FLOOR_PROBE_HEIGHT, 0)
		if Workspace:Raycast(origin, Vector3.new(0, -depth, 0)) then
			continue
		end

		local floor: Part = Instance.new("Part")
		floor.Name = `Floor{index}`
		floor.Anchored = true
		floor.Size = Vector3.new(area.size.X, FLOOR_THICKNESS, area.size.Y)
		floor.Position = area.center - Vector3.new(0, FLOOR_THICKNESS / 2, 0)
		floor.Parent = folder
	end
end

--[[
    Starts a scenario's load for one seed: clears any bots an earlier run
    left, sets the real players at the viewer point and spawns every group.
    Returns the stop that destroys the bots, and on a failed spawn destroys
    what it made before passing the error on
--]]

function Bots.start(scenario: Scenario, seed: number): () -> ()
	local leftover: Instance? = Workspace:FindFirstChild(BOTS_NAME)
	if leftover then
		leftover:Destroy()
	end

	local folder: Folder = Instance.new("Folder")
	folder.Name = BOTS_NAME
	folder.Parent = Workspace

	local viewer: Vector3? = scenario.viewer
	if viewer then
		placeViewers(viewer)
	end

	local spawned: boolean, problem: any = pcall(spawnAll, scenario, seed, folder)
	if not spawned then
		folder:Destroy()
		error(problem, 0)
	end

	-- Destroying the folder destroys every bot, and with them every connection their Humanoids hold
	return function ()
		folder:Destroy()
	end
end

return Bots
