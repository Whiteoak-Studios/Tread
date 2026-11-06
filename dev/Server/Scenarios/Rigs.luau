--[[
    Poses the rig fixture's pool over a floor and a step it builds under
    Workspace.SpikeFixtures, with clips it registers itself: placing, tracks,
    the layer, planted feet, markers, the draw distance and the ragdoll
--]]

--!strict
local AnimationClipProvider = game:GetService("AnimationClipProvider")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local Engine = require(ReplicatedStorage.Packages.Tread.Step.Engine)
local Rig = require(ServerScriptService.Fixtures.Rigs.Rig)
local Rigs = require(ReplicatedStorage.Packages.Tread.Client.Rigs)
local State = require(ReplicatedStorage.Packages.Tread.Step.State)

local FIXTURE_HEIGHT: number = 1010 -- Studs; the floor's top, above the 1,000 no content reaches
local FLOOR_SIZE: Vector3 = Vector3.new(60, 1, 60)
local STEP_SIZE: Vector3 = Vector3.new(1.5, 1, 2) -- Under rig A's left foot alone
local STEP_CENTER_X: number = -10.75
local A_X: number = -10 -- Where each rig stands
local B_X: number = 10
local PITCH: number = 0.4 -- Radians rig A aims up by
local LEAN: number = 12 -- Degrees rig A leans right by
local TURNED: number = math.pi / 2 -- Rig B's facing, which looks along -X
local WALK_SPEED: number = 10 -- Studs a second rig A walks at, in place
local CLIP_LENGTH: number = 1 -- Seconds each registered clip runs before it loops
local SWING: number = 0.5 -- Radians the walk clip swings each thigh by
local MARKER: string = "Step"
local MARKER_VALUE: string = "left"
local SETTLE_SECONDS: number = 0.5 -- How long the still rigs are posed before they are measured
local READINGS: number = 7 -- How many times rig A's planted foot is read on the step
local READ_EVERY: number = 0.25 -- Seconds between those readings, so the seven span 1.5 s
local MARKER_SECONDS: number = 3 -- How long rig A walks waiting for its marker
local RAGDOLL_MARGIN: number = 1 -- Seconds past bodies.maxSeconds the scenario waits for a freeze
local ANGLE_TOLERANCE: number = 0.5 -- Degrees
local FOOT_TOLERANCE: number = 0.2 -- Studs
local PLACE_TOLERANCE: number = 0.01 -- Studs
local PUSHED: number = 0.25 -- Studs the pushed torso must cross before it freezes
local FELL: number = 1 -- Studs the torso must fall
local SEPARATOR: string = "; "
local LISTED: string = ", "

-- The left leg's joints the bend turns, by their logical names
local LEFT_LEG: { string } = { "LeftHip", "LeftKnee", "LeftAnkle" }

-- The states the still clip plays for, and those the walk clip does
local WALKING: { [string]: boolean } = { walk = true, sprint = true, crouchWalk = true, crawl = true, swim = true }
local STATES: { string } = {
	"idle",
	"walk",
	"sprint",
	"crouchIdle",
	"crouchWalk",
	"jump",
	"fall",
	"land",
	"swimIdle",
	"swim",
	"climb",
	"mantle",
	"downed",
	"crawl",
}

type Call = Rig.Call
type Collision = State.Collision
type Pool = Rigs.Rigs
type State = State.State

-- What the run made that the scenario removes on every path
type Made = {
	collision: Collision?,
	rigs: Pool?,
	disconnect: (() -> ())?,
	measuring: RBXScriptConnection?,
}

-- The largest angle any axis turns between two CFrames, from the chord between the axes, exact near zero
local function degrees(from: CFrame, to: CFrame): number
	local chord: number = math.max(
		(from.XVector - to.XVector).Magnitude,
		(from.YVector - to.YVector).Magnitude,
		(from.ZVector - to.ZVector).Magnitude
	)

	return math.deg(2 * math.asin(math.min(chord / 2, 1)))
end

--[[
    A looping clip, registered for this session, swinging the thighs by
    swing each way, with the marker at its middle keyframe when one is given
--]]

local function clip(swing: number, marker: string?): Animation
	local sequence: KeyframeSequence = Instance.new("KeyframeSequence")
	sequence.Loop = true

	local times: { number } = { 0, CLIP_LENGTH / 2, CLIP_LENGTH }
	for index: number, time: number in times do
		local keyframe: Keyframe = Instance.new("Keyframe")
		keyframe.Time = time

		local root: Pose = Instance.new("Pose")
		root.Name = "HumanoidRootPart"
		root.Weight = 0
		local hips: Pose = Instance.new("Pose")
		hips.Name = "LowerTorso"
		root:AddSubPose(hips)

		-- The middle keyframe swings the other way
		local direction: number = index == 2 and -1 or 1
		local left: Pose = Instance.new("Pose")
		left.Name = "LeftUpperLeg"
		left.CFrame = CFrame.Angles(swing * direction, 0, 0)
		hips:AddSubPose(left)
		local right: Pose = Instance.new("Pose")
		right.Name = "RightUpperLeg"
		right.CFrame = CFrame.Angles(-swing * direction, 0, 0)
		hips:AddSubPose(right)

		keyframe:AddPose(root)

		if marker and index == 2 then
			local reached: KeyframeMarker = Instance.new("KeyframeMarker")
			reached.Name = marker
			reached.Value = MARKER_VALUE
			keyframe:AddMarker(reached)
		end

		sequence:AddKeyframe(keyframe)
	end

	local animation: Animation = Instance.new("Animation")
	animation.AnimationId = AnimationClipProvider:RegisterAnimationClip(sequence)

	return animation
end

local function part(name: string, size: Vector3, center: Vector3, parent: Instance)
	local made: Part = Instance.new("Part")
	made.Name = name
	made.Anchored = true
	made.CanCollide = true
	made.CanQuery = true
	made.CanTouch = false
	made.Size = size
	made.CFrame = CFrame.new(center)
	made.Parent = parent
end

local function standing(x: number, facing: number): State
	local state: State = State.new()
	state.position = vector.create(x, FIXTURE_HEIGHT, 0)
	state.facing = facing
	state.mode = "Ground"
	state.grounded = true

	return state
end

-- The upper torso's place in the lower torso's space, which the waist's layer turns
local function waist(rig: Model): CFrame
	local lower = rig:FindFirstChild("LowerTorso") :: BasePart
	local upper = rig:FindFirstChild("UpperTorso") :: BasePart

	local relative: CFrame = lower.CFrame:ToObjectSpace(upper.CFrame)

	return relative
end

local function footHeight(rig: Model): number
	return (rig:FindFirstChild("LeftFoot") :: BasePart).Position.Y
end

local function named(instance: Instance?): string
	return instance and instance:GetFullName() or "nil"
end

local function round(value: number): string
	return string.format("%.3f", value)
end

--[[
    What rig A's left foot was planted from, for a foot that left the step:
    the step's own ray cast where the pool casts it, how far the bend turns
    each joint of the left leg, the foot before its first step and now, and
    the tracks playing
--]]

local function planting(rig: Model, collision: Collision, before: number): string
	local template: Model = Rig.template()
	local templateRoot = template.PrimaryPart :: BasePart
	local templateFoot = template:FindFirstChild("LeftFoot") :: BasePart
	local reach: number = templateRoot.Position.Y
	local offset: Vector3 = templateRoot.CFrame:PointToObjectSpace(templateFoot.Position)

	local root = rig.PrimaryPart :: BasePart
	local at: Vector3 = root.CFrame:PointToWorldSpace(offset)
	local hit: State.Hit? =
		collision.ray(vector.create(at.X, FIXTURE_HEIGHT + reach, at.Z), vector.create(0, -2 * reach, 0))
	local seen: string = "nil"
	if hit then
		seen = `{named(hit.instance)} at height {hit.position.y}`
	end

	-- How far each joint of the left leg turns from its rest, as the last step left it
	local turns: { string } = {}
	for _, logical: string in LEFT_LEG do
		local joint = rig:FindFirstChild(Rig.joints[logical], true) :: AnimationConstraint
		table.insert(turns, `{logical} {round(degrees(CFrame.identity, joint.Transform))} deg`)
	end

	local controller = rig:FindFirstChildOfClass("AnimationController") :: AnimationController
	local animator = controller:FindFirstChildOfClass("Animator") :: Animator
	local playing: { string } = {}
	for _, track: AnimationTrack in animator:GetPlayingAnimationTracks() do
		table.insert(playing, `{track.Animation and track.Animation.AnimationId} weight {track.WeightCurrent}`)
	end

	local tracks: string = #playing > 0 and table.concat(playing, LISTED) or "none"
	local feet: string = `foot {before} after the first pose, {footHeight(rig)} now`

	return `ray hit {seen}; turned {table.concat(turns, LISTED)}; {feet}; tracks playing: {tracks}`
end

-- Whether a rig plays a track of the animation
local function plays(rig: Model, animation: Animation): boolean
	local controller = rig:FindFirstChildOfClass("AnimationController") :: AnimationController
	local animator = controller:FindFirstChildOfClass("Animator") :: Animator
	for _, track: AnimationTrack in animator:GetPlayingAnimationTracks() do
		if track.Animation == animation then
			return true
		end
	end

	return false
end

-- Poses rig A and rig B every frame until the deadline, or until done says so
local function poseFor(rigs: Pool, a: State, b: State, seconds: number, done: (() -> boolean)?)
	local deadline: number = os.clock() + seconds
	while os.clock() < deadline do
		rigs:pose(0, a, 0, PITCH)
		rigs:pose(1, b, 0, 0)

		if done and done() then
			return
		end

		RunService.Heartbeat:Wait()
	end
end

-- Whether a ragdoll has frozen: every part anchored and its machinery gone
local function frozen(rig: Model): boolean
	for _, item: Instance in rig:GetDescendants() do
		if item:IsA("BasePart") and not item.Anchored then
			return false
		end

		local machinery: boolean = item:IsA("AnimationConstraint")
			or item:IsA("BallSocketConstraint")
			or item:IsA("AnimationController")
		if machinery then
			return false
		end
	end

	return true
end

local function run(problems: { string }, folder: Folder, made: Made)
	part("Floor", FLOOR_SIZE, Vector3.new(0, FIXTURE_HEIGHT - FLOOR_SIZE.Y / 2, 0), folder)
	part("Step", STEP_SIZE, Vector3.new(STEP_CENTER_X, FIXTURE_HEIGHT + STEP_SIZE.Y / 2, 0), folder)

	local collision: Collision = Engine.collision({ folder })
	made.collision = collision

	local still: Animation = clip(0, nil)
	local walk: Animation = clip(SWING, MARKER)
	local animations: { [string]: Animation } = {}
	for _, state: string in STATES do
		animations[state] = WALKING[state] and walk or still
	end

	local calls: { Call } = {}
	local rigs: Pool = Rigs.new(Rig.settings(calls, animations), Rig.drawDistance, collision)
	made.rigs = rigs

	local heard: { string } = {}
	made.disconnect = rigs:onMarker(function (slot: number, marker: string, value: string)
		table.insert(heard, `{slot} {marker} {value}`)
	end)

	-- 1) Two still rigs: A aiming up and leaning with its left foot over the step, B turned on the flat
	local a: Model = rigs:checkout(0, {})
	local b: Model = rigs:checkout(1, {})
	local stateA: State = standing(A_X, 0)
	stateA.lean = LEAN
	local stateB: State = standing(B_X, TURNED)

	local turned: number? = nil
	local measuring: RBXScriptConnection = RunService.PostSimulation:Connect(function ()
		turned = degrees(waist(a), waist(b))
	end)
	made.measuring = measuring

	-- The foot where the first pose leaves it, before any step bends its leg
	rigs:pose(0, stateA, 0, PITCH)
	rigs:pose(1, stateB, 0, 0)
	local posed: number = os.clock()
	local before: number = footHeight(a)

	poseFor(rigs, stateA, stateB, SETTLE_SECONDS)
	measuring:Disconnect()

	local expected: number = degrees(CFrame.identity, CFrame.Angles(PITCH, 0, -math.rad(LEAN)))
	if turned == nil or math.abs(turned - expected) > ANGLE_TOLERANCE then
		table.insert(problems, `rig A's waist turned {turned} deg past rig B's, where the layer turns {expected}`)
	end

	local rootHeight: number = (Rig.template().PrimaryPart :: BasePart).Position.Y
	local placed: Vector3 = (a.PrimaryPart :: BasePart).Position
	local wanted: Vector3 = Vector3.new(A_X, FIXTURE_HEIGHT + rootHeight, 0)
	if (placed - wanted).Magnitude > PLACE_TOLERANCE then
		table.insert(problems, `rig A's root sits at {placed}, not {wanted}`)
	end

	local looking: Vector3 = (b.PrimaryPart :: BasePart).CFrame.LookVector
	if (looking - Vector3.new(-1, 0, 0)).Magnitude > PLACE_TOLERANCE then
		table.insert(problems, `rig B, facing pi/2, looks along {looking}, not -X`)
	end

	if not plays(a, still) or not plays(b, still) then
		table.insert(problems, "a still rig does not play the idle state's clip")
	end

	local lift: number = (Rig.template():FindFirstChild("LeftFoot") :: BasePart).Position.Y
	local onStep: number = FIXTURE_HEIGHT + STEP_SIZE.Y + lift
	local onFloor: number = FIXTURE_HEIGHT + lift
	if math.abs(footHeight(b) - onFloor) > FOOT_TOLERANCE then
		table.insert(problems, `rig B's left foot stands at {footHeight(b)}, not on the floor at {onFloor}`)
	end

	-- Rig A's planted foot must hold on the step, so it is read at moments across the span while both stay posed
	local readings: { string } = {}
	local off: boolean = false
	local holding: number = os.clock()
	poseFor(rigs, stateA, stateB, READ_EVERY * READINGS, function (): boolean
		local now: number = os.clock()
		if now - holding < READ_EVERY * #readings then
			return false
		end

		local height: number = footHeight(a)
		table.insert(readings, `{round(height)} at {round(now - posed)} s`)
		if math.abs(height - onStep) > FOOT_TOLERANCE then
			off = true
		end

		return #readings >= READINGS
	end)

	local heights: string = table.concat(readings, LISTED)
	print(`Rigs: rig A's left foot against the step at {round(onStep)}: {heights}`)
	if off or #readings < READINGS then
		local seen: string = planting(a, collision, before)
		local read: string = `{#readings} of {READINGS} readings`
		table.insert(
			problems,
			`rig A's left foot did not hold on the step at {round(onStep)} in {read}: {heights}; {seen}`
		)
	end

	-- 2) Rig A walks in place until its walk clip's marker reaches the callback
	stateA.velocity = vector.create(0, 0, -WALK_SPEED)
	stateA.lean = 0
	poseFor(rigs, stateA, stateB, MARKER_SECONDS, function (): boolean
		return #heard > 0
	end)

	if not plays(a, walk) then
		table.insert(problems, "a walking rig does not play the walk state's clip")
	end

	local wantedMarker: string = `0 {MARKER} {MARKER_VALUE}`
	if heard[1] ~= wantedMarker then
		local reason: string = `rig A's walk raised {heard[1] or "no marker"} within {MARKER_SECONDS} s`
		table.insert(problems, `{reason}, not {wantedMarker}; a warning above names an unread clip`)
	end

	-- 3) Past the draw distance the rig leaves Workspace, and back inside it returns
	rigs:pose(0, stateA, Rig.drawDistance + 1, 0)
	if a.Parent ~= nil then
		table.insert(problems, "rig A stayed in Workspace past the draw distance")
	end
	rigs:pose(0, stateA, 0, 0)
	if a.Parent == nil then
		table.insert(problems, "rig A did not come back inside the draw distance")
	end

	-- 4) Rig A dies, re-keyed to slot 2, pushed along -Z, and freezes where it settles
	local torso = a:FindFirstChild("UpperTorso") :: BasePart
	local died: Vector3 = torso.Position
	rigs:ragdoll(0, 2, vector.create(0, 0, -1))

	local deadline: number = os.clock() + Rig.bodies.maxSeconds + RAGDOLL_MARGIN
	while not frozen(a) and os.clock() < deadline do
		rigs:pose(1, stateB, 0, 0)
		RunService.Heartbeat:Wait()
	end

	local travel: Vector3 = torso.Position - died
	if not frozen(a) then
		table.insert(
			problems,
			`rig A's ragdoll had not frozen {Rig.bodies.maxSeconds + RAGDOLL_MARGIN} s after its death`
		)
	elseif Vector3.new(travel.X, 0, travel.Z).Magnitude < PUSHED or -travel.Y < FELL then
		table.insert(problems, `rig A's torso moved {travel} from where it died, not pushed and fallen`)
	end

	-- 5) The body's release destroys its rig, and the other goes back to the pool
	table.clear(calls)
	rigs:release(2)
	rigs:release(1)
	if a.Parent ~= nil or #calls ~= 2 or calls[1].rig ~= a or calls[2].rig ~= b then
		table.insert(problems, "the releases did not undress both rigs once and take both out of Workspace")
	end

	local released: boolean = pcall(rigs.pose, rigs, 2, stateA, 0, 0)
	if released then
		table.insert(problems, "a pose of the released body's slot was taken")
	end
end

return function (): (boolean, string | nil)
	local problems: { string } = {}

	local root: Instance? = Workspace:FindFirstChild("SpikeFixtures")
	local madeRoot: boolean = root == nil
	if not root then
		local fixtures: Folder = Instance.new("Folder")
		fixtures.Name = "SpikeFixtures"
		fixtures.Parent = Workspace
		root = fixtures
	end

	local folder: Folder = Instance.new("Folder")
	folder.Name = "Rigs"
	folder.Parent = root

	local made: Made = {}
	local ran: boolean, failure: any = pcall(run, problems, folder, made)
	if not ran then
		table.insert(problems, `the scenario threw: {failure}`)
	end

	-- Everything it made goes, whatever the run did
	local measuring: RBXScriptConnection? = made.measuring
	if measuring then
		measuring:Disconnect()
	end

	local disconnect: (() -> ())? = made.disconnect
	if disconnect then
		disconnect()
	end

	local rigs: Pool? = made.rigs
	if rigs then
		rigs:destroy()
	end

	local collision: Collision? = made.collision
	if collision then
		collision.destroy()
	end

	folder:Destroy()
	if madeRoot and root and #root:GetChildren() == 0 then
		root:Destroy()
	end

	if Workspace:FindFirstChild("TreadRigs") then
		table.insert(problems, "the pool's folder was left in Workspace")
	end

	if #problems > 0 then
		return false, table.concat(problems, SEPARATOR)
	end

	return true, nil
end
