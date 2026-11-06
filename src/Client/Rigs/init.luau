--[[
    The client's rig pool: rigs cloned from the game's template, dressed for
    a slot and given back, posed from a step state at the detail their
    distance earns, and ragdolled when they die
--]]

--!strict
local Rigs = {}
Rigs.__index = Rigs

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Animate = require(script.Animate)
local Constants = require(script.Parent.Parent.Constants)
local Ragdoll = require(script.Ragdoll)
local State = require(script.Parent.Parent.Step.State)

local SLOTS: number = Constants.SLOTS
local MOVE_EVENTS: Enum.BulkMoveMode = Enum.BulkMoveMode.FireCFrameChanged -- A placed root fires only its CFrame change

-- The 15 R15 joints mode A's adapter maps, each a logical name the game's joints map names an instance for
local JOINTS: { string } = {
	"Root",
	"Waist",
	"Neck",
	"LeftShoulder",
	"LeftElbow",
	"LeftWrist",
	"RightShoulder",
	"RightElbow",
	"RightWrist",
	"LeftHip",
	"LeftKnee",
	"LeftAnkle",
	"RightHip",
	"RightKnee",
	"RightAnkle",
}

type Animated = Animate.Animated
type Collision = State.Collision
type Place = Animate.Place
type State = State.State
type Values = State.Values

export type Animations = Animate.Animations
export type Bodies = Ragdoll.Bodies
export type Limit = Ragdoll.Limit

-- A slot's look and its held item, the game's declared fields by name
export type Outfit = Values
export type Held = Values

-- Each logical joint's name in the game's rig template
export type Joints = { [string]: string }

-- The animation detail distances, studs: full detail, planted feet and aim pitch
export type Lod = {
	full: number,
	footIk: number,
	aim: number,
}

-- The client settings the pool reads, under their own keys
export type Settings = {
	rig: Model,
	joints: Joints,
	animations: Animations,
	dress: (rig: Model, outfit: Outfit, copy: boolean) -> (),
	undress: (rig: Model) -> (),
	hold: (rig: Model, held: Held?) -> (),
	lod: Lod,
	bodies: Bodies,
}

export type Marker = (slot: number, marker: string, value: string) -> ()

type Entry = {
	rig: Model,
	root: BasePart,
	joints: { [string]: AnimationConstraint }, -- Its own joint instances, by logical name
	slot: number?, -- The slot it is checked out for, nil while pooled
	holding: boolean, -- Whether hold has put an item on it
	drawn: boolean, -- Whether it is in Workspace, inside the draw distance
	placed: vector?, -- Where its last pose put its feet, nil before the first
	facing: number,
	animated: Animated?, -- Its tracks, from its first draw until it ragdolls
	body: Ragdoll.Body?, -- Its ragdoll, once it dies
}

type Fields = {
	_settings: Settings,
	_drawDistance: number,
	_collision: Collision,
	_rootHeight: number, -- The template's root above its lowest point, so a rig's feet stand on a state's position
	_places: { Place },
	_folder: Folder,
	_pool: { Entry }, -- Rigs ready for a slot, out of Workspace
	_slots: { [number]: Entry },
	_rigs: { Entry }, -- Every rig built and not yet destroyed, pooled or not
	_markers: { [string]: { string } }, -- Each animation's marker names by its AnimationId, once read
	_reading: { [string]: boolean }, -- The AnimationIds whose markers are being or have been read
	_listeners: { [{ nil }]: Marker },
	_layering: RBXScriptConnection?, -- The PreSimulation layer, from the first draw until destroy
	_moved: { BasePart }, -- BulkMoveTo's lists, reused for every pose
	_targets: { CFrame },
	_destroyed: boolean,
}

-- Errors naming a value that is no slot, from the caller of the member named
local function checkSlot(slot: number, member: string)
	if type(slot) ~= "number" or slot % 1 ~= 0 or slot < 0 or slot >= SLOTS then
		error(`Rigs.{member} takes a slot from 0 to {SLOTS - 1}, not {slot}`, 3)
	end
end

-- The joint instance a rig holds for a logical joint, erroring naming what is missing
local function jointOf(rig: Model, names: Joints, logical: string): AnimationConstraint
	local name: string? = names[logical]
	if type(name) ~= "string" then
		error(`The joints map names no joint for {logical}`, 3)
	end

	local found: Instance? = rig:FindFirstChild(name, true)
	if not found or not found:IsA("AnimationConstraint") then
		error(`The rig {rig.Name} has no AnimationConstraint named {name} for {logical}`, 3)
	end

	local attachment1: Attachment? = found.Attachment1
	if not found.Attachment0 or not attachment1 or not attachment1.Parent or not attachment1.Parent:IsA("BasePart") then
		error(`The rig {rig.Name}'s {name} joins no two parts by their attachments`, 3)
	end

	return found
end

local function partOf(joint: AnimationConstraint): BasePart
	return (joint.Attachment1 :: Attachment).Parent :: BasePart
end

-- The lowest point of any part of a model, each part's extent along the world's Y read from its axes
local function lowest(model: Model): number
	local bottom: number = math.huge
	for _, item: Instance in model:GetDescendants() do
		if item:IsA("BasePart") then
			local frame: CFrame = item.CFrame
			local size: Vector3 = item.Size
			local x: number = math.abs(frame.RightVector.Y) * size.X
			local y: number = math.abs(frame.UpVector.Y) * size.Y
			local z: number = math.abs(frame.LookVector.Y) * size.Z
			bottom = math.min(bottom, frame.Position.Y - (x + y + z) / 2)
		end
	end

	return bottom
end

-- Removes an entry from a list, wherever it sits
local function forget(list: { Entry }, entry: Entry)
	local index: number? = table.find(list, entry)
	if index then
		table.remove(list, index)
	end
end

-- Runs where a callback's error was raised, so its warning keeps the callback's stack
local function warnFailure(message: any)
	warn(`A marker callback threw, and the other callbacks still ran: {debug.traceback(tostring(message), 2)}`)
end

--[[
    A pool over the game's rig template, checked against what the pool
    needs from it: a PrimaryPart as its root, an AnimationController with
    an Animator, each R15 joint as a kinematic AnimationConstraint, legs
    whose knees can bend, an Animation for every state and the limits of
    every joint but Root

    @ drawDistance | this device class's character draw distance
    @ collision | the step's own casts, which feet are planted with
--]]

function Rigs.new(settings: Settings, drawDistance: number, collision: Collision): Self
	local template: Model = settings.rig
	if typeof(template) ~= "Instance" or not template:IsA("Model") then
		error(`Rigs.new takes a Model as the rig template, not a {typeof(template)}`, 2)
	elseif not template.Archivable then
		error(`The rig template {template.Name} is not Archivable, so it can't be cloned`, 2)
	end

	local root: BasePart? = template.PrimaryPart
	if not root then
		error(`The rig template {template.Name} has no PrimaryPart, the root its rigs are placed by`, 2)
	end

	local controller: AnimationController? = template:FindFirstChildOfClass("AnimationController")
	if not controller or not controller:FindFirstChildOfClass("Animator") then
		error(`The rig template {template.Name} has no AnimationController with an Animator`, 2)
	end

	local joints: { [string]: AnimationConstraint } = {}
	for _, logical: string in JOINTS do
		joints[logical] = jointOf(template, settings.joints, logical)
	end

	Animate.check(settings.animations)
	Ragdoll.check(settings.bodies, JOINTS)

	if type(drawDistance) ~= "number" or not (drawDistance > 0) then
		error(`Rigs.new takes a draw distance above 0, not {drawDistance}`, 2)
	elseif type(collision) ~= "table" or type(collision.ray) ~= "function" then
		error("Rigs.new takes the step's Collision, whose ray plants the feet", 2)
	end

	-- How each leg bends and where its foot sits on the template, which every rig shares
	local places: { Place } = Animate.places(root, joints)
	local rootHeight: number = root.CFrame.Position.Y - lowest(template)

	local folder: Folder = Instance.new("Folder")
	folder.Name = "TreadRigs"
	folder.Parent = Workspace

	return setmetatable({
		_settings = settings,
		_drawDistance = drawDistance,
		_collision = collision,
		_rootHeight = rootHeight,
		_places = places,
		_folder = folder,
		_pool = {} :: { Entry },
		_slots = {} :: { [number]: Entry },
		_rigs = {} :: { Entry },
		_markers = {} :: { [string]: { string } },
		_reading = {} :: { [string]: boolean },
		_listeners = {} :: { [{ nil }]: Marker },
		_layering = nil :: RBXScriptConnection?,
		_moved = {} :: { BasePart },
		_targets = {} :: { CFrame },
		_destroyed = false,
	}, Rigs)
end

--[[
    A rig dressed for a slot with the slot's look: one back from the pool,
    or a new clone of the template when the pool is empty. It stays out of
    Workspace until its first pose draws it
--]]

function Rigs.checkout(self: Self, slot: number, outfit: Outfit): Model
	checkSlot(slot, "checkout")
	if self._slots[slot] then
		error(`Slot {slot} already has a rig checked out`, 2)
	elseif type(outfit) ~= "table" then
		error(`Rigs.checkout takes the slot's look as a table, not a {typeof(outfit)}`, 2)
	end

	local entry: Entry = table.remove(self._pool) or self:_build()
	local copy: boolean = false -- A world rig, never the first-person copy

	self._settings.dress(entry.rig, outfit, copy)
	entry.slot = slot
	self._slots[slot] = entry

	return entry.rig
end

function Rigs._build(self: Self): Entry
	local settings: Settings = self._settings
	local rig: Model = settings.rig:Clone()

	local joints: { [string]: AnimationConstraint } = {}
	for _, logical: string in JOINTS do
		joints[logical] = jointOf(rig, settings.joints, logical)
	end

	local entry: Entry = {
		rig = rig,
		root = rig.PrimaryPart :: BasePart,
		joints = joints,
		slot = nil,
		holding = false,
		drawn = false,
		placed = nil,
		facing = 0,
		animated = nil,
		body = nil,
	}
	table.insert(self._rigs, entry)

	return entry
end

function Rigs._entry(self: Self, slot: number, member: string): Entry
	local entry: Entry? = self._slots[slot]
	if not entry then
		error(`Rigs.{member} takes a slot with a rig checked out, not {slot}`, 3)
	end

	return entry
end

--[[
    Puts a new look on a slot's rig, the old one taken off first
--]]

function Rigs.dress(self: Self, slot: number, outfit: Outfit)
	local entry: Entry = self:_entry(slot, "dress")
	if type(outfit) ~= "table" then
		error(`Rigs.dress takes the slot's look as a table, not a {typeof(outfit)}`, 2)
	end

	local copy: boolean = false -- A world rig, never the first-person copy
	self._settings.undress(entry.rig)
	self._settings.dress(entry.rig, outfit, copy)
end

--[[
    Puts the held item a slot's held-item fields name on its rig, or clears
    the hands with nil
--]]

function Rigs.hold(self: Self, slot: number, held: Held?)
	local entry: Entry = self:_entry(slot, "hold")
	self._settings.hold(entry.rig, held)
	entry.holding = held ~= nil
end

--[[
    Undresses a slot's rig and gives it back to the pool, its held item
    cleared first. A rig that ragdolled is a body, which leaves the pool, so
    it is destroyed instead
--]]

function Rigs.release(self: Self, slot: number)
	local entry: Entry = self:_entry(slot, "release")
	local settings: Settings = self._settings

	self._slots[slot] = nil
	entry.slot = nil

	local animated: Animated? = entry.animated
	if animated then
		Animate.stop(animated)
	end

	if entry.holding then
		settings.hold(entry.rig, nil)
		entry.holding = false
	end
	settings.undress(entry.rig)

	local body: Ragdoll.Body? = entry.body
	if body then
		Ragdoll.stop(body)
		forget(self._rigs, entry)
		entry.rig:Destroy()
		return
	end

	entry.rig.Parent = nil
	entry.drawn = false
	table.insert(self._pool, entry)
end

--[[
    Poses a slot's rig from a step state at its distance from the viewer:
    out of Workspace past the draw distance, and inside it placed by its
    root, playing the state's track, with its lean, its aim within lod.aim,
    full detail within lod.full and its feet planted within lod.footIk. A
    ragdoll is left to its physics. Past a rig's first draw it makes no
    table, closure or string; a move, a new aim or lean and a planted foot's
    cast make the engine's own CFrames and results

    @ distance | studs from the viewer's eye to the rig
    @ pitch | the character's aim pitch, radians, up positive
--]]

function Rigs.pose(self: Self, slot: number, state: State, distance: number, pitch: number)
	local entry: Entry = self:_entry(slot, "pose")
	if entry.body then
		return
	end

	if distance > self._drawDistance then
		if entry.drawn then
			entry.drawn = false
			entry.rig.Parent = nil

			local animated: Animated? = entry.animated
			if animated then
				Animate.stop(animated)
			end
		end

		return
	end

	if not entry.drawn then
		entry.drawn = true
		entry.rig.Parent = self._folder
	end

	local animated: Animated = entry.animated or self:_animate(entry)

	-- The root goes where the state's feet are, turned to its facing, once the place changes
	local position: vector = state.position
	local moved: boolean = position ~= entry.placed or state.facing ~= entry.facing
	if moved then
		entry.placed = position
		entry.facing = state.facing

		-- Whiteoak TODO: one BulkMoveTo per drawn rig; gather a frame's roots into one call once the client
		-- handle has a point after its last pose of the frame, if G5 shows what the per-rig call costs
		local height: number = position.y + self._rootHeight
		self._moved[1] = entry.root
		self._targets[1] = CFrame.new(position.x, height, position.z) * CFrame.Angles(0, state.facing, 0)
		Workspace:BulkMoveTo(self._moved, self._targets, MOVE_EVENTS)
	end

	local lod: Lod = self._settings.lod
	local full: boolean = distance <= lod.full
	local velocity: vector = state.velocity

	-- Whiteoak TODO: feet plant only while the body stands still; plant each foot through its walk's stance
	-- too, from the foot's own speed, if playtests show feet sliding or floating on slopes and stairs
	local planting: boolean = distance <= lod.footIk
		and state.mode == "Ground"
		and state.posture ~= "Downed"
		and velocity.x == 0
		and velocity.z == 0

	Animate.detail(animated, full)
	Animate.pose(animated, state, full)
	Animate.aim(animated, distance <= lod.aim and pitch or 0, state.lean)
	Animate.plant(animated, entry.root, position.y, self._rootHeight, self._collision, planting, moved)
end

--[[
    Loads a rig's tracks at its first draw, starts the layer the first time
    any rig is drawn, and connects the markers of every animation whose
    names are read, reading the rest
--]]

function Rigs._animate(self: Self, entry: Entry): Animated
	local settings: Settings = self._settings
	local animated: Animated = Animate.load(
		entry.rig,
		entry.joints,
		settings.animations,
		self._places,
		function (marker: string, value: string)
			self:_publish(entry, marker, value)
		end
	)
	entry.animated = animated

	-- Disconnected by destroy
	if not self._layering then
		self._layering = RunService.PreSimulation:Connect(function ()
			self:_layer()
		end)
	end

	for state: string in animated.tracks do
		local animation: Animation = settings.animations[state]
		local id: string = animation.AnimationId
		local names: { string }? = self._markers[id]

		if names then
			Animate.watch(animated, state, names)
		elseif not self._reading[id] then
			self:_read(id, animation)
		end
	end

	return animated
end

--[[
    Reads an animation's marker names on a thread of its own, then connects
    them on every rig loaded by then. The engine's read ends the thread, by
    answering or by erroring, and a pool destroyed meanwhile drops it
--]]

function Rigs._read(self: Self, id: string, animation: Animation)
	self._reading[id] = true

	task.spawn(function ()
		local read: boolean, result: any = pcall(Animate.markers, animation)
		if self._destroyed then
			return
		end

		local names: { string } = {}
		if read then
			names = result
		else
			warn(`Tread raises no markers of {id}, since its clip could not be read: {result}`)
		end
		self._markers[id] = names

		for _, entry: Entry in self._rigs do
			local animated: Animated? = entry.animated
			if animated then
				for state: string in animated.tracks do
					if self._settings.animations[state].AnimationId == id then
						Animate.watch(animated, state, names)
					end
				end
			end
		end
	end)
end

-- The aim and lean layer and the planted legs of every drawn rig, at each simulation step
function Rigs._layer(self: Self)
	for _, entry: Entry in self._slots do
		local animated: Animated? = entry.animated
		if animated and entry.drawn then
			Animate.layer(animated)
		end
	end
end

--[[
    Tells every marker callback of a marker a rig reached, with the slot it
    is drawn for. Each runs under its own xpcall, so one that throws is
    warned with its stack and never stops the others
--]]

function Rigs._publish(self: Self, entry: Entry, marker: string, value: string)
	local slot: number? = entry.slot
	if slot == nil then
		return
	end

	-- A copy, so a callback connected mid-fire waits for the next marker and one disconnected mid-fire is skipped
	for token: { nil }, callback: Marker in table.clone(self._listeners) do
		if self._listeners[token] then
			xpcall(callback, warnFailure, slot, marker, value)
		end
	end
end

--[[
    Ragdolls a dying slot's rig, re-keyed to its body's slot: its tracks
    stop at once and its joints go limp under the bodies settings, pushed
    along the death's attack direction, none for a death with no push

    @ body | the body's slot, which the rig is drawn for from now on
    @ push | the attack's direction, nil for no push
--]]

function Rigs.ragdoll(self: Self, slot: number, body: number, push: vector?)
	local entry: Entry = self:_entry(slot, "ragdoll")
	if entry.body then
		error(`Slot {slot}'s rig is already a ragdoll`, 2)
	end

	checkSlot(body, "ragdoll")
	if body ~= slot and self._slots[body] then
		error(`Slot {body} already has a rig, so slot {slot}'s body can't take its rig`, 2)
	end

	self._slots[slot] = nil
	self._slots[body] = entry
	entry.slot = body

	if not entry.drawn then
		entry.drawn = true
		entry.rig.Parent = self._folder
	end

	local animated: Animated? = entry.animated
	if animated then
		Animate.stop(animated)
		Animate.release(animated)
		entry.animated = nil
	end

	local bodies: Bodies = self._settings.bodies
	local torso: BasePart = partOf(entry.joints.Waist)
	entry.body = Ragdoll.start(entry.rig, entry.joints, torso, bodies, Ragdoll.push(push, bodies))
end

--[[
    Calls back on every animation marker a drawn rig's track reaches, with
    its slot, the marker's name and its value. Returns the closure that
    disconnects the callback
--]]

function Rigs.onMarker(self: Self, callback: Marker): () -> ()
	if type(callback) ~= "function" then
		error(`Rigs.onMarker takes a function, not a {typeof(callback)}`, 2)
	end

	local token: { nil } = {}
	self._listeners[token] = callback

	-- Cleanup
	return function ()
		self._listeners[token] = nil
	end
end

--[[
    Destroys every rig, pooled, drawn or lying, disconnects the layer and
    every marker callback, and cancels each ragdoll's next check
--]]

function Rigs.destroy(self: Self)
	self._destroyed = true

	local layering: RBXScriptConnection? = self._layering
	if layering then
		layering:Disconnect()
		self._layering = nil
	end

	for _, entry: Entry in self._rigs do
		local body: Ragdoll.Body? = entry.body
		if body then
			Ragdoll.stop(body)
		end

		local animated: Animated? = entry.animated
		if animated then
			Animate.release(animated)
		end

		entry.rig:Destroy()
	end

	table.clear(self._rigs)
	table.clear(self._pool)
	table.clear(self._slots)
	table.clear(self._listeners)
	self._folder:Destroy()
end

export type Rigs = Self
type Self = typeof(setmetatable({} :: Fields, Rigs))

return Rigs
