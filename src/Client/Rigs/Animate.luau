--[[
    What a drawn rig plays: one track per locomotion state, loaded once, the
    one a step state picks, the aim and lean layer, feet planted by each
    leg's own bend while it stands still, and the markers its tracks reach
--]]

--!strict
--!native
local AnimationClipProvider = game:GetService("AnimationClipProvider")

local State = require(script.Parent.Parent.Parent.Step.State)

local INSTANT: number = 0 -- Seconds a stop fades over, so the pose drops at once
local AUTHORED: number = 1 -- A track's speed as it was authored
local HELD: number = 0 -- A track's speed while it holds its pose
local ROOT: string = "Root" -- The joint the legs hang from, between the root part and the hips
local NEARLY: number = 1e-6 -- The shortest length, or the widest a cross of two directions, that still points a way
local FORWARD: vector = vector.create(0, 0, -1) -- The rig's facing in its root's space, the way every knee bends
local UP: vector = vector.create(0, 1, 0) -- The rig's up in its root's space, which a hinge falls back on

-- The legs whose feet plant, by their logical joints from the hip down
local LEGS: { { hip: string, knee: string, ankle: string } } = {
	{ hip = "LeftHip", knee = "LeftKnee", ankle = "LeftAnkle" },
	{ hip = "RightHip", knee = "RightKnee", ankle = "RightAnkle" },
}

-- The locomotion states Tread plays, each one Animation in the game's animations map
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

type Collision = State.Collision
type State = State.State

export type Animations = { [string]: Animation }

-- What a marker one of the rig's tracks reaches calls, with the marker's name and value
export type Fire = (marker: string, value: string) -> ()

-- A rotation by the directions it turns the X, Y and Z axes to, and a place
export type Frame = {
	x: vector,
	y: vector,
	z: vector,
	p: vector,
}

-- How one leg of the template bends, which every rig built from it shares, all in its root's space
export type Place = {
	hip: string, -- The leg's logical joints
	knee: string,
	ankle: string,
	foot: Vector3, -- The foot's center, which its ray is cast under
	rest: vector, -- The ankle's pivot at rest, which a planted target raises or lowers
	line: vector, -- The way from the hip's pivot to the ankle's at rest
	upper: number, -- The bones' lengths, pivot to pivot
	lower: number,
	base: Frame, -- The Root's C0, the hips' frame before their pose
	mount: Frame, -- The hip's C0 in the space the Root's pose turns
	hipInThigh: Frame, -- The hip's rest axes in the rest thigh's bend axes
	thighInKnee: Frame, -- The rest thigh's bend axes in the knee's rest axes
	kneeInShin: Frame, -- The knee's rest axes in the rest shin's bend axes
	shinInAnkle: Frame, -- The rest shin's bend axes in the ankle's rest axes
	ankleAxes: Frame, -- The ankle's rest axes
}

-- One rig's leg: its own joints, and where its ankle goes while its foot is planted
export type Leg = {
	place: Place,
	hip: AnimationConstraint,
	knee: AnimationConstraint,
	ankle: AnimationConstraint,
	target: vector, -- Where the ankle's pivot goes, in the root's space
	planted: boolean, -- Whether its ray found ground
}

export type Animated = {
	animator: Animator,
	tracks: { [string]: AnimationTrack }, -- One per state, by the state's name
	playing: AnimationTrack?, -- The locomotion track now playing
	land: AnimationTrack,
	lands: number?, -- The land counter the last pose saw, nil before the first
	waist: AnimationConstraint, -- The joint the aim and lean layer turns
	root: AnimationConstraint, -- The joint the legs hang from, whose pose they read at each step
	pitch: number, -- Radians
	lean: number, -- Degrees
	tilt: CFrame, -- The layer both make
	tilted: boolean, -- Whether the layer turns anything
	detailed: boolean, -- Whether the Animator is asked to evaluate at full fidelity
	planted: boolean, -- Whether the feet are planted
	legs: { Leg },
	connections: { RBXScriptConnection }, -- The marker connections, which release disconnects
	watched: { [string]: boolean }, -- The states whose markers are connected
	fire: Fire,
}

local Animate = {}

--[[
    Errors naming the first state the game's animations map gives no
    Animation for
--]]

function Animate.check(animations: Animations)
	for _, state: string in STATES do
		local animation: Animation? = animations[state]
		if typeof(animation) ~= "Instance" or not animation:IsA("Animation") then
			error(`The animations map gives no Animation for {state}`, 3)
		end
	end
end

-- A rotation's columns applied to a direction
local function turn(x: vector, y: vector, z: vector, direction: vector): vector
	return x * direction.x + y * direction.y + z * direction.z
end

-- A direction in a rotation's own axes, the rotation undone
local function unturn(x: vector, y: vector, z: vector, direction: vector): vector
	return vector.create(vector.dot(x, direction), vector.dot(y, direction), vector.dot(z, direction))
end

-- A Transform that moves nothing and turns by the rotation whose columns these are
local function rotation(x: vector, y: vector, z: vector): CFrame
	return CFrame.new(0, 0, 0, x.x, y.x, z.x, x.y, y.y, z.y, x.z, y.z, z.z)
end

local function frameOf(cframe: CFrame): Frame
	local px: number, py: number, pz: number, r00: number, r01: number, r02: number, r10: number, r11: number, r12: number, r20: number, r21: number, r22: number =
		cframe:GetComponents()

	return {
		x = vector.create(r00, r10, r20),
		y = vector.create(r01, r11, r21),
		z = vector.create(r02, r12, r22),
		p = vector.create(px, py, pz),
	}
end

-- One frame in another's axes: the other undone, then this one
local function within(other: Frame, frame: Frame): Frame
	return {
		x = unturn(other.x, other.y, other.z, frame.x),
		y = unturn(other.x, other.y, other.z, frame.y),
		z = unturn(other.x, other.y, other.z, frame.z),
		p = unturn(other.x, other.y, other.z, frame.p - other.p),
	}
end

-- A bone's bend axes: the hinge made square to the bone, the way back up the bone, and the axis both make
local function axes(hinge: vector, bone: vector): Frame?
	local square: vector = hinge - bone * vector.dot(hinge, bone)
	local width: number = vector.magnitude(square)
	if width < NEARLY then
		return nil
	end

	local x: vector = square / width
	local y: vector = -bone

	return { x = x, y = y, z = vector.cross(x, y), p = vector.zero }
end

-- A joint's two attachments' offsets, its C0 in the part it hangs from and its C1 in the part it moves
local function offsets(joint: AnimationConstraint): (CFrame, CFrame)
	return (joint.Attachment0 :: Attachment).CFrame, (joint.Attachment1 :: Attachment).CFrame
end

--[[
    One leg of the template, read from its joints with no pose on them, or
    why it can't bend: joints that don't chain from the root part down, a
    bone of no length, or a leg along the facing, which gives its knee no
    way to bend
--]]

local function measure(
	root: BasePart,
	joints: { [string]: AnimationConstraint },
	hip: string,
	knee: string,
	ankle: string
): (Place?, string | nil)
	local leg: string = `{hip}, {knee} and {ankle}`

	-- 1) Each joint hangs from the part the one above it moves, the Root from the root part
	local holder: Instance? = root
	local chain: { string } = { ROOT, hip, knee, ankle }
	for _, name: string in chain do
		local joint: AnimationConstraint = joints[name]
		if (joint.Attachment0 :: Attachment).Parent ~= holder then
			return nil, `The rig template's {name} joint doesn't hang from the part above it in the leg {leg}`
		end

		holder = (joint.Attachment1 :: Attachment).Parent
	end

	-- 2) Each pivot at rest, in the root part's space
	local rootC0: CFrame, rootC1: CFrame = offsets(joints[ROOT])
	local hipC0: CFrame, hipC1: CFrame = offsets(joints[hip])
	local kneeC0: CFrame, kneeC1: CFrame = offsets(joints[knee])
	local ankleC0: CFrame, ankleC1: CFrame = offsets(joints[ankle])

	local mount: CFrame = rootC1:Inverse() * hipC0
	local hipRest: CFrame = rootC0 * mount
	local kneeRest: CFrame = hipRest * hipC1:Inverse() * kneeC0
	local ankleRest: CFrame = kneeRest * kneeC1:Inverse() * ankleC0
	local footRest: CFrame = ankleRest * ankleC1:Inverse()

	local hipFrame: Frame = frameOf(hipRest)
	local kneeFrame: Frame = frameOf(kneeRest)
	local ankleFrame: Frame = frameOf(ankleRest)

	local upperBone: vector = kneeFrame.p - hipFrame.p
	local lowerBone: vector = ankleFrame.p - kneeFrame.p
	local upper: number = vector.magnitude(upperBone)
	local lower: number = vector.magnitude(lowerBone)
	if upper < NEARLY or lower < NEARLY then
		return nil, `The rig template's leg {leg} has a bone of no length`
	end

	-- 3) The rest axes: the hinge across the leg's line and the facing, made square to each bone
	local span: vector = ankleFrame.p - hipFrame.p
	local reach: number = vector.magnitude(span)
	local thigh: Frame? = nil
	local shin: Frame? = nil

	if reach > NEARLY then
		local across: vector = vector.cross(span / reach, FORWARD)
		local width: number = vector.magnitude(across)

		if width > NEARLY then
			thigh = axes(across / width, upperBone / upper)
			shin = axes(across / width, lowerBone / lower)
		end
	end

	if thigh and shin then
		local place: Place = {
			hip = hip,
			knee = knee,
			ankle = ankle,
			foot = footRest.Position,
			rest = ankleFrame.p,
			line = span / reach,
			upper = upper,
			lower = lower,
			base = frameOf(rootC0),
			mount = frameOf(mount),
			hipInThigh = within(thigh, hipFrame),
			thighInKnee = within(kneeFrame, thigh),
			kneeInShin = within(shin, kneeFrame),
			shinInAnkle = within(ankleFrame, shin),
			ankleAxes = ankleFrame,
		}

		return place, nil
	end

	return nil, `The rig template's leg {leg} points along the rig's facing at rest, so its knee has no way to bend`
end

--[[
    How each leg of the game's rig template bends, read once from its
    joints: the chain from the root part down, the bones' lengths and the
    rest axes, which every rig built from it shares. Errors naming the
    first leg whose joints don't chain, whose bone has no length or that
    points along the rig's facing

    @ root | the template's PrimaryPart, which the Root joint hangs from
    @ joints | the template's own joint instances, by logical name
--]]

function Animate.places(root: BasePart, joints: { [string]: AnimationConstraint }): { Place }
	local places: { Place } = {}
	for _, names in LEGS do
		local place: Place?, problem: string? = measure(root, joints, names.hip, names.knee, names.ankle)
		if not place then
			error(problem, 3)
		end

		table.insert(places, place)
	end

	return places
end

--[[
    Each leg of one rig, its own joints over the places every rig shares,
    unplanted

    @ joints | the rig's own joint instances, by logical name
--]]

function Animate.legs(joints: { [string]: AnimationConstraint }, places: { Place }): { Leg }
	local legs: { Leg } = {}
	for _, place: Place in places do
		table.insert(legs, {
			place = place,
			hip = joints[place.hip],
			knee = joints[place.knee],
			ankle = joints[place.ankle],
			target = place.rest,
			planted = false,
		})
	end

	return legs
end

--[[
    Loads every state's track once onto a rig in Workspace, with its legs
    unplanted until a pose plants them

    @ joints | the rig's own joint instances, by logical name
    @ fire | what each marker a track reaches calls once watch connects it
--]]

function Animate.load(
	rig: Model,
	joints: { [string]: AnimationConstraint },
	animations: Animations,
	places: { Place },
	fire: Fire
): Animated
	local controller: AnimationController? = rig:FindFirstChildOfClass("AnimationController")
	local animator: Animator? = controller and controller:FindFirstChildOfClass("Animator")
	if not controller or not animator then
		error(`The rig {rig:GetFullName()} has no AnimationController with an Animator`, 2)
	end

	local tracks: { [string]: AnimationTrack } = {}
	for _, state: string in STATES do
		tracks[state] = animator:LoadAnimation(animations[state])
	end

	-- A landing plays once over the locomotion track, whatever its animation was authored as
	local land: AnimationTrack = tracks.land
	land.Looped = false

	return {
		animator = animator,
		tracks = tracks,
		playing = nil,
		land = land,
		lands = nil,
		waist = joints.Waist,
		root = joints[ROOT],
		pitch = 0,
		lean = 0,
		tilt = CFrame.identity,
		tilted = false,
		detailed = false,
		planted = false,
		legs = Animate.legs(joints, places),
		connections = {},
		watched = {},
		fire = fire,
	}
end

--[[
    The state a step state's track is named for. The mode picks first, then
    the posture, and idle and walk come from the horizontal speed
--]]

function Animate.choose(state: State): string
	local velocity: vector = state.velocity
	local moving: boolean = velocity.x ~= 0 or velocity.z ~= 0
	local mode: string = state.mode

	if mode == "Mantle" then
		return "mantle"
	elseif mode == "Ladder" then
		return "climb"
	elseif mode == "Swim" then
		return moving and "swim" or "swimIdle"
	elseif mode == "Air" then
		return velocity.y > 0 and "jump" or "fall"
	end

	local posture: string = state.posture
	if posture == "Downed" then
		return moving and "crawl" or "downed"
	elseif posture == "Crouch" then
		return moving and "crouchWalk" or "crouchIdle"
	elseif moving then
		return state.sprint and "sprint" or "walk"
	end

	return "idle"
end

--[[
    Plays the track the state picks, fading from the one before, holds a
    climb still while the climber is, and plays a landing once when the
    state's land counter moves and the rig is drawn at full detail
--]]

function Animate.pose(animated: Animated, state: State, full: boolean)
	local name: string = Animate.choose(state)
	local track: AnimationTrack = animated.tracks[name]

	if track ~= animated.playing then
		local playing: AnimationTrack? = animated.playing
		if playing then
			playing:Stop()
		end

		track:Play()
		animated.playing = track
	end

	if name == "climb" then
		local still: boolean = state.velocity == vector.zero
		track:AdjustSpeed(still and HELD or AUTHORED)
	end

	local lands: number = state.lands
	if animated.lands ~= nil and lands ~= animated.lands and full then
		animated.land:Play()
	end
	animated.lands = lands
end

--[[
    Asks the Animator for full fidelity inside the full-detail distance,
    and leaves it to the engine's throttling beyond
--]]

function Animate.detail(animated: Animated, full: boolean)
	if full ~= animated.detailed then
		animated.detailed = full
		animated.animator.PreferLodEnabled = not full
	end
end

--[[
    Sets the layer the waist takes each step: the aim's pitch turning the
    upper body up or down, and the lean tilting it sideways, a positive
    lean to the right
--]]

function Animate.aim(animated: Animated, pitch: number, lean: number)
	if pitch == animated.pitch and lean == animated.lean then
		return
	end

	animated.pitch = pitch
	animated.lean = lean
	animated.tilt = CFrame.Angles(pitch, 0, -math.rad(lean))
	animated.tilted = pitch ~= 0 or lean ~= 0
end

--[[
    Bends one planted leg so its ankle's pivot meets its target, from the
    hips' pose this step: the knee ahead of the line from the hip to the
    target, along the rig's facing, and the leg straight toward a target
    out of reach. Each Transform turns its joint's axes from where they
    rest to where the bend puts them: the hip by the thigh's, the knee by
    the shin's against the thigh's, and the ankle back by the shin's, so
    the foot keeps the way it rests

    @ tx | the hips' pose this step, its rotation's columns and its move
--]]

local function bend(leg: Leg, tx: vector, ty: vector, tz: vector, tp: vector)
	local place: Place = leg.place
	local base: Frame = place.base
	local mount: Frame = place.mount

	-- 1) The hip's pivot and axes under the hips' pose
	local lx: vector = turn(base.x, base.y, base.z, tx)
	local ly: vector = turn(base.x, base.y, base.z, ty)
	local lz: vector = turn(base.x, base.y, base.z, tz)
	local lp: vector = base.p + turn(base.x, base.y, base.z, tp)

	local hx: vector = turn(lx, ly, lz, mount.x)
	local hy: vector = turn(lx, ly, lz, mount.y)
	local hz: vector = turn(lx, ly, lz, mount.z)
	local hip: vector = lp + turn(lx, ly, lz, mount.p)

	-- 2) The way to the target, and the hinge across it and the facing, which the knee turns about
	local line: vector = leg.target - hip
	local distance: number = vector.magnitude(line)
	local along: vector = place.line
	if distance > NEARLY then
		along = line / distance
	end

	local hinge: vector = vector.cross(along, FORWARD)
	local width: number = vector.magnitude(hinge)
	if width > NEARLY then
		hinge /= width
	else
		hinge = vector.normalize(vector.cross(along, UP))
	end
	local ahead: vector = vector.cross(hinge, along)

	-- 3) The bones from the law of cosines, the reach held between folded and straight
	local upper: number = place.upper
	local lower: number = place.lower
	local reach: number = math.clamp(distance, math.max(math.abs(upper - lower), NEARLY), upper + lower)
	local cosine: number = math.clamp((upper * upper + reach * reach - lower * lower) / (2 * upper * reach), -1, 1)
	local thigh: vector = along * cosine + ahead * math.sqrt(1 - cosine * cosine)
	local shin: vector = vector.normalize(along * reach - thigh * upper)

	-- The bent bones' axes, the hinge first, as the place's rest axes are built
	local thighY: vector = -thigh
	local thighZ: vector = vector.cross(hinge, thighY)
	local shinY: vector = -shin
	local shinZ: vector = vector.cross(hinge, shinY)

	-- 4) The hip, against the axes the hips' pose leaves it in
	local hipInThigh: Frame = place.hipInThigh
	local hipX: vector = turn(hinge, thighY, thighZ, hipInThigh.x)
	local hipY: vector = turn(hinge, thighY, thighZ, hipInThigh.y)
	local hipZ: vector = turn(hinge, thighY, thighZ, hipInThigh.z)
	leg.hip.Transform = rotation(unturn(hx, hy, hz, hipX), unturn(hx, hy, hz, hipY), unturn(hx, hy, hz, hipZ))

	-- 5) The knee, by the shin's axes in the thigh's
	local kneeInShin: Frame = place.kneeInShin
	local thighInKnee: Frame = place.thighInKnee
	local sx: vector = unturn(hinge, thighY, thighZ, hinge)
	local sy: vector = unturn(hinge, thighY, thighZ, shinY)
	local sz: vector = unturn(hinge, thighY, thighZ, shinZ)
	local kneeX: vector = turn(sx, sy, sz, kneeInShin.x)
	local kneeY: vector = turn(sx, sy, sz, kneeInShin.y)
	local kneeZ: vector = turn(sx, sy, sz, kneeInShin.z)
	leg.knee.Transform = rotation(
		turn(thighInKnee.x, thighInKnee.y, thighInKnee.z, kneeX),
		turn(thighInKnee.x, thighInKnee.y, thighInKnee.z, kneeY),
		turn(thighInKnee.x, thighInKnee.y, thighInKnee.z, kneeZ)
	)

	-- 6) The ankle, the shin's turn undone
	local ankleAxes: Frame = place.ankleAxes
	local shinInAnkle: Frame = place.shinInAnkle
	local ankleX: vector = unturn(hinge, shinY, shinZ, ankleAxes.x)
	local ankleY: vector = unturn(hinge, shinY, shinZ, ankleAxes.y)
	local ankleZ: vector = unturn(hinge, shinY, shinZ, ankleAxes.z)
	leg.ankle.Transform = rotation(
		turn(shinInAnkle.x, shinInAnkle.y, shinInAnkle.z, ankleX),
		turn(shinInAnkle.x, shinInAnkle.y, shinInAnkle.z, ankleY),
		turn(shinInAnkle.x, shinInAnkle.y, shinInAnkle.z, ankleZ)
	)
end

--[[
    Writes the layer over the pose the Animator just wrote: the waist's
    tilt on top of it, and each planted leg bent to its target. It runs in
    PreSimulation at every simulation step, since the Animator rewrites
    each Transform at every step, and the frame's last step's write is the
    one drawn. A throttled Animator leaves the last step's Transforms,
    layer and all, so writing them again would stack the tilt
--]]

function Animate.layer(animated: Animated)
	if not (animated.tilted or animated.planted) or animated.animator.EvaluationThrottled then
		return
	end

	if animated.tilted then
		local waist: AnimationConstraint = animated.waist
		waist.Transform = animated.tilt * waist.Transform
	end

	if not animated.planted then
		return
	end

	-- Whiteoak TODO: a planted rig reads its hips' pose and makes a CFrame for each leg joint at every step; keep
	-- the last ones while that pose and the targets hold, if G5 shows what they cost
	local px: number, py: number, pz: number, r00: number, r01: number, r02: number, r10: number, r11: number, r12: number, r20: number, r21: number, r22: number =
		animated.root.Transform:GetComponents()

	local tx: vector = vector.create(r00, r10, r20)
	local ty: vector = vector.create(r01, r11, r21)
	local tz: vector = vector.create(r02, r12, r22)
	local tp: vector = vector.create(px, py, pz)

	for _, leg: Leg in animated.legs do
		if leg.planted then
			bend(leg, tx, ty, tz, tp)
		end
	end
end

--[[
    Plants each foot on the ground under where it stands on the template,
    found with the step's own ray, for the layer to bend its leg to, or
    lets the animation move the feet again. A foot over nothing is left to
    the animation, and a planted rig that has not moved keeps its targets

    @ feet | the height of the state's position, where the hull's bottom is
    @ reach | the rig's root height above its feet; the cast runs from that
    high above the feet to as far below them
--]]

function Animate.plant(
	animated: Animated,
	root: BasePart,
	feet: number,
	reach: number,
	collision: Collision,
	planting: boolean,
	moved: boolean
)
	if not planting then
		animated.planted = false
		return
	elseif animated.planted and not moved then
		return
	end

	animated.planted = true

	local frame: CFrame = root.CFrame
	local top: number = feet + reach
	local down: vector = vector.create(0, -2 * reach, 0)

	for _, leg: Leg in animated.legs do
		local place: Place = leg.place
		local at: Vector3 = frame:PointToWorldSpace(place.foot)
		local hit: State.Hit? = collision.ray(vector.create(at.X, top, at.Z), down)

		-- The ankle rises or drops from its rest by the ground's height above the feet
		leg.planted = hit ~= nil
		if hit then
			leg.target = place.rest + vector.create(0, hit.position.y - feet, 0)
		end
	end
end

--[[
    Stops every track at once and lets the feet go, for a rig that leaves
    Workspace, goes back to the pool or ragdolls. The next pose plays from
    the start and plays no landing for the land it missed
--]]

function Animate.stop(animated: Animated)
	local playing: AnimationTrack? = animated.playing
	if playing then
		playing:Stop(INSTANT)
		animated.playing = nil
	end

	animated.land:Stop(INSTANT)
	animated.lands = nil
	animated.planted = false
end

--[[
    Connects each named marker of one state's track to the rig's fire,
    once per state
--]]

function Animate.watch(animated: Animated, state: string, names: { string })
	local track: AnimationTrack? = animated.tracks[state]
	if not track or animated.watched[state] then
		return
	end

	animated.watched[state] = true

	local fire: Fire = animated.fire
	for _, name: string in names do
		local connection: RBXScriptConnection = track:GetMarkerReachedSignal(name):Connect(function (value: string)
			fire(name, value)
		end)

		table.insert(animated.connections, connection)
	end
end

--[[
    The names of every marker an animation's clip holds, a KeyframeSequence's
    KeyframeMarkers and a CurveAnimation's MarkerCurves alike. It yields
    while the engine reads the clip, and errors when it can't
--]]

function Animate.markers(animation: Animation): { string }
	local clip: AnimationClip = AnimationClipProvider:GetAnimationClipAsync(animation.AnimationId)

	local names: { string } = {}
	for _, item: Instance in clip:GetDescendants() do
		local marker: boolean = item:IsA("KeyframeMarker") or item:IsA("MarkerCurve")
		if marker and not table.find(names, item.Name) then
			table.insert(names, item.Name)
		end
	end

	return names
end

--[[
    Disconnects every marker connection and lets the feet go, for a rig
    that ragdolls or is destroyed
--]]

function Animate.release(animated: Animated)
	for _, connection: RBXScriptConnection in animated.connections do
		connection:Disconnect()
	end
	table.clear(animated.connections)

	animated.planted = false
end

return Animate
