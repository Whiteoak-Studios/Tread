--[[
    The client's rig pool: rigs cloned from the game's template, dressed for
    a slot and given back, posed at the detail their distance earns, laid down
    or ragdolled as bodies, outlined for spectate, and the owner's own view
--]]

--!strict
local Rigs = {}
Rigs.__index = Rigs

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Animate = require(script.Animate)
local Config = require(script.Parent.Parent.Config)
local Constants = require(script.Parent.Parent.Constants)
local FirstPerson = require(script.FirstPerson)
local Ragdoll = require(script.Ragdoll)
local State = require(script.Parent.Parent.Step.State)

local SLOTS: number = Constants.SLOTS
local MOVE_EVENTS: Enum.BulkMoveMode = Enum.BulkMoveMode.FireCFrameChanged -- A placed root fires only its CFrame change
local WORLD_RIG: boolean = false -- The dress hook's copy flag for a world rig, the body other viewers see
local FIRST_PERSON: boolean = true -- Its flag for the owner's copy, which leaves off what the copy never shows
local NEAR: number = 0 -- Studs from the eye the copy is posed at, since the eye is inside it, so at full detail
local LEVEL: number = 0 -- The copy's aim pitch, radians: the torso turns with the camera for other viewers only
local OUTLINED: string = "TreadOutlined" -- The model the outlined rigs are drawn in, under the one Highlight
local THROUGH_WALLS: Enum.HighlightDepthMode = Enum.HighlightDepthMode.AlwaysOnTop -- The outline shows through walls

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
type ClientSettings = Config.ClientSettings
type Collision = State.Collision
type Place = Animate.Place
type State = State.State
type World = State.World

-- The client settings' keys the pool reads, each typed where the client settings declare it
export type Joints = index<ClientSettings, "joints">
export type Animations = index<ClientSettings, "animations">
export type Lod = index<ClientSettings, "lod">
export type Bodies = index<ClientSettings, "bodies">
export type Limit = index<index<Bodies, "jointLimits">, string>
export type Spectate = index<ClientSettings, "spectate">

-- A slot's look and its held item, the game's declared fields by name
export type Outfit = State.Values
export type Held = State.Values

-- The client settings the pool reads, under their own keys
export type Settings = {
	rig: index<ClientSettings, "rig">,
	joints: Joints,
	animations: Animations,
	dress: index<ClientSettings, "dress">,
	undress: index<ClientSettings, "undress">,
	hold: index<ClientSettings, "hold">,
	lod: Lod,
	bodies: Bodies,
	read spectate: Spectate?, -- Read the first time a rig is outlined, which errors without it
}

export type Marker = (slot: number, marker: string, value: string) -> ()

type Entry = {
	rig: Model,
	root: BasePart,
	joints: { [string]: AnimationConstraint }, -- Its own joint instances, by logical name
	slot: number?, -- The slot it is checked out for, nil while pooled
	holding: boolean, -- Whether hold has put an item on it
	drawn: boolean, -- Whether it is in Workspace, inside the draw distance
	outlined: boolean, -- Whether it is drawn under the spectate outline
	placed: vector?, -- Where its last pose put its feet, nil before the first
	facing: number,
	animated: Animated?, -- Its tracks, from its first draw until it ragdolls
	body: Ragdoll.Body?, -- Its ragdoll, once it dies
}

type Fields = {
	_settings: Settings,
	_drawDistance: number,
	_collision: Collision,
	_world: World?, -- The world whose casts each plant reads as they stand then, nil to plant through _collision
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
	_own: number?, -- The slot checked out as the local player's own, nil while none is
	_copy: Entry?, -- Its first-person copy, held apart from every slot, nil while it has none
	_watched: number?, -- The spectated target's slot, whose world rig takes the local player's rig setting
	_firstPerson: FirstPerson.FirstPerson, -- What the local player sees of their own rigs
	_container: Model?, -- What the outlined rigs are drawn in, made the first time one is
	_destroyed: boolean,
}

local Thrown: string = "" -- The last world rig's dress hook error, with its stack, which checkout raises again

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

-- Runs where a rig hook raised an error for the owner's first-person copy, so its warning keeps the hook's stack
local function warnCopy(message: unknown)
	local stack: string = debug.traceback(tostring(message), 2)
	warn(`A rig hook threw for the first-person copy, and its world rig carried on without it: {stack}`)
end

-- Runs where an undress hook raised an error on a rig whose dress threw, so its warning keeps the hook's stack
local function warnUndress(message: unknown)
	local stack: string = debug.traceback(tostring(message), 2)
	warn(`A rig's undress hook threw after its dress hook did, so the rig was destroyed: {stack}`)
end

-- Keeps the error a world rig's dress hook raised with the stack that raised it, taken before the stack unwinds
local function keep(message: unknown)
	Thrown = debug.traceback(tostring(message), 2)
end

-- Takes a rig's look off and puts a new one on
local function restyle(settings: Settings, rig: Model, outfit: Outfit, copy: boolean)
	settings.undress(rig)
	settings.dress(rig, outfit, copy)
end

-- The aim and lean layer and the planted legs of one rig, if it is drawn
local function layer(entry: Entry)
	local animated: Animated? = entry.animated
	if animated and entry.drawn then
		Animate.layer(animated)
	end
end

--[[
    A pool over the game's rig template, checked against what the pool
    needs from it: a PrimaryPart as its root, an AnimationController with
    an Animator, each R15 joint as a kinematic AnimationConstraint, legs
    whose knees can bend, an Animation for every state and the limits of
    every joint but Root

    @ drawDistance | this device class's character draw distance
    @ collision | the step's own casts, which feet are planted with
    @ world | the world whose casts feet are planted with in place of
    collision, read at each plant, since a platform wraps them later
--]]

function Rigs.new(settings: Settings, drawDistance: number, collision: Collision, world: World?): Self
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
	elseif world ~= nil and (type(world) ~= "table" or type(world.collision) ~= "table") then
		error(`Rigs.new takes the step's World, whose casts plant the feet, or none, not a {typeof(world)}`, 2)
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
		_world = world,
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
		_own = nil :: number?,
		_copy = nil :: Entry?,
		_watched = nil :: number?,
		_firstPerson = FirstPerson.new(),
		_container = nil :: Model?,
		_destroyed = false,
	}, Rigs)
end

--[[
    A rig dressed for a slot with the slot's look: one back from the pool,
    or a new clone of the template when the pool is empty. It stays out of
    Workspace until its first pose draws it. The local player's own rig is
    hidden on this screen, and a second rig from the pool comes out with it
    as its first-person copy. A dress hook that throws gives the rig back
    and raises its error again, with the hook's stack

    @ own | whether the slot is the local player's own
--]]

function Rigs.checkout(self: Self, slot: number, outfit: Outfit, own: boolean?): Model
	checkSlot(slot, "checkout")
	if self._slots[slot] then
		error(`Slot {slot} already has a rig checked out`, 2)
	elseif type(outfit) ~= "table" then
		error(`Rigs.checkout takes the slot's look as a table, not a {typeof(outfit)}`, 2)
	elseif own and self._own ~= nil then
		error(`Slot {self._own}'s rig is already the local player's own, so slot {slot}'s can't be`, 2)
	end

	local entry: Entry = table.remove(self._pool) or self:_build()
	local dressed: boolean = xpcall(self._settings.dress, keep, entry.rig, outfit, WORLD_RIG)
	if not dressed then
		self:_giveBack(entry)
		error(Thrown, 0)
	end

	entry.slot = slot
	self._slots[slot] = entry

	if own then
		local copy: Entry? = self:_take(outfit)
		self._own = slot
		self._copy = copy
		self._firstPerson:build(entry.rig, copy)
	end

	return entry.rig
end

--[[
    The local player's first-person copy, a rig from the pool dressed with
    their look as the copy and held apart from every slot, so its markers
    reach nobody. A dress hook that throws is warned, and gives the rig back
    with no copy
--]]

function Rigs._take(self: Self, outfit: Outfit): Entry?
	local entry: Entry = table.remove(self._pool) or self:_build()
	local dressed: boolean = xpcall(self._settings.dress, warnCopy, entry.rig, outfit, FIRST_PERSON)
	if not dressed then
		self:_giveBack(entry)
		return nil
	end

	return entry
end

--[[
    Gives back a rig whose dress hook threw before any slot held it:
    undressed under its own guard and pooled, or, when its undress throws
    too, destroyed and dropped from the pool's rigs
--]]

function Rigs._giveBack(self: Self, entry: Entry)
	local undressed: boolean = xpcall(self._settings.undress, warnUndress, entry.rig)
	if undressed then
		table.insert(self._pool, entry)
		return
	end

	local animated: Animated? = entry.animated
	if animated then
		Animate.release(animated)
	end

	forget(self._rigs, entry)
	entry.rig:Destroy()
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
		outlined = false,
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
    Puts a new look on a slot's rig, the old one taken off first, and on
    the local player's own first-person copy too, each of their parts then
    hidden on this screen as before, as are the spectated target's
--]]

function Rigs.dress(self: Self, slot: number, outfit: Outfit)
	local entry: Entry = self:_entry(slot, "dress")
	if type(outfit) ~= "table" then
		error(`Rigs.dress takes the slot's look as a table, not a {typeof(outfit)}`, 2)
	end

	local settings: Settings = self._settings
	restyle(settings, entry.rig, outfit, WORLD_RIG)

	if slot == self._own then
		local copy: Entry? = self._copy
		if copy then
			xpcall(restyle, warnCopy, settings, copy.rig, outfit, FIRST_PERSON)
		end

		self._firstPerson:refresh()
	elseif slot == self._watched then
		self._firstPerson:refresh()
	end
end

--[[
    Puts the held item a slot's held-item fields name on its rig, or clears
    the hands with nil, and on the local player's own first-person copy
    too, each of their parts then hidden on this screen as before, as are
    the spectated target's
--]]

function Rigs.hold(self: Self, slot: number, held: Held?)
	local entry: Entry = self:_entry(slot, "hold")
	local settings: Settings = self._settings
	settings.hold(entry.rig, held)
	entry.holding = held ~= nil

	if slot == self._own then
		local copy: Entry? = self._copy
		if copy then
			local holds: boolean = xpcall(settings.hold, warnCopy, copy.rig, held)
			if holds then
				copy.holding = held ~= nil
			end
		end

		self._firstPerson:refresh()
	elseif slot == self._watched then
		self._firstPerson:refresh()
	end
end

--[[
    Undresses a slot's rig and gives it back to the pool, its held item
    cleared first, and the local player's own first-person copy with it. A
    rig that ragdolled is a body, which leaves the pool, so it is destroyed
    instead
--]]

function Rigs.release(self: Self, slot: number)
	local entry: Entry = self:_entry(slot, "release")
	if slot == self._own then
		self:_disown()
	elseif slot == self._watched then
		self:watch(nil)
	end

	self._slots[slot] = nil
	entry.slot = nil
	self:_put(entry)
end

--[[
    Ends the local player's own rig as their own: both their rigs shown on
    this screen again, as the pool and a body need them, and the copy back
    in the pool, its hooks under their own guard
--]]

function Rigs._disown(self: Self)
	self._own = nil
	self._firstPerson:release()

	local copy: Entry? = self._copy
	if copy then
		self._copy = nil
		xpcall(self._put, warnCopy, self, copy)
	end
end

-- Stops, clears and undresses a rig no slot holds any more, then pools it, or destroys it once it is a body
function Rigs._put(self: Self, entry: Entry)
	local settings: Settings = self._settings

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
	entry.outlined = false
	table.insert(self._pool, entry)
end

--[[
    Poses a slot's rig from a step state at its distance from the viewer:
    out of Workspace past the draw distance, and inside it placed by its
    root, playing the state's track, with its lean, its aim within lod.aim,
    full detail within lod.full and its feet planted within lod.footIk. A
    ragdoll is left to its physics. The local player's own first-person
    copy is posed from the same state where its world rig stands, at full
    detail, leaning with no aim pitch. Past a rig's first draw it makes no
    table, closure or string; a move, a new aim or lean and a planted foot's
    cast make the engine's own CFrames and results

    @ distance | studs from the viewer's eye to the rig
    @ pitch | the character's aim pitch, radians, up positive
--]]

function Rigs.pose(self: Self, slot: number, state: State, distance: number, pitch: number)
	local entry: Entry = self:_entry(slot, "pose")
	self:_draw(entry, state, distance, pitch)

	local copy: Entry? = self._copy
	if copy and slot == self._own then
		self:_draw(copy, state, NEAR, LEVEL)
	end
end

function Rigs._draw(self: Self, entry: Entry, state: State, distance: number, pitch: number)
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
		entry.rig.Parent = self:_holder(entry)
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

	-- The world's casts as they stand at this plant, since the first platform registered wraps them after the start
	-- Whiteoak TODO: a plant meets a moving platform's boxes on the world's tick, the owner's newest predicted one,
	-- up to a tick of the platform's move from the copy drawn; cast against the boxes at the copy's drawn place once
	-- a playtest shows feet off a moving lift
	local collision: Collision = self._collision
	local world: World? = self._world
	if world then
		collision = world.collision
	end

	Animate.detail(animated, full)
	Animate.pose(animated, state, full)
	Animate.aim(animated, distance <= lod.aim and pitch or 0, state.lean)
	Animate.plant(animated, entry.root, position.y, self._rootHeight, collision, planting, moved)
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

-- The aim and lean layer and the planted legs of every drawn rig, the copy's included, at each simulation step
function Rigs._layer(self: Self)
	for _, entry: Entry in self._slots do
		layer(entry)
	end

	local copy: Entry? = self._copy
	if copy then
		layer(copy)
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
    along the death's attack direction, none for a death with no push. The
    local player's own rig shows on this screen again as a body, and its
    first-person copy goes back to the pool

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

	self:_rekey(entry, slot, body)

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
    Lays a dying slot's rig down as its body, re-keyed to the body's slot
    with no ragdoll, for a client too far from the death or reached too
    late: its tracks stop at once, so its next pose plays the lying clip
    from the start, and it stays a drawn rig posed like any other. The
    local player's own rig shows on this screen again as a body, and its
    first-person copy goes back to the pool

    @ body | the body's slot, which the rig is drawn for from now on
--]]

function Rigs.lie(self: Self, slot: number, body: number)
	local entry: Entry = self:_entry(slot, "lie")
	if entry.body then
		error(`Slot {slot}'s rig is already a ragdoll`, 2)
	end

	checkSlot(body, "lie")
	if body ~= slot and self._slots[body] then
		error(`Slot {body} already has a rig, so slot {slot}'s body can't take its rig`, 2)
	end

	self:_rekey(entry, slot, body)

	local animated: Animated? = entry.animated
	if animated then
		Animate.stop(animated)
	end
end

--[[
    Keys a dying slot's rig to its body's slot, a body no longer the local
    player's own, the spectated target or outlined
--]]

function Rigs._rekey(self: Self, entry: Entry, slot: number, body: number)
	if slot == self._own then
		self:_disown()
	elseif slot == self._watched then
		self:watch(nil)
	end

	if entry.outlined then
		entry.outlined = false

		if entry.drawn then
			entry.rig.Parent = self._folder
		end
	end

	self._slots[slot] = nil
	self._slots[body] = entry
	entry.slot = body
end

--[[
    Names the spectated target's slot, whose world rig takes the local
    player's own "rig" setting on this screen as their own does, its look
    and held item included; nil for none. Its rig must be checked out, and
    the slot is let go of when the rig is released or becomes a body
--]]

function Rigs.watch(self: Self, slot: number?)
	if slot == nil then
		self._watched = nil
		self._firstPerson:watch(nil)

		return
	end

	local entry: Entry = self:_entry(slot, "watch")
	self._watched = slot
	self._firstPerson:watch(entry.rig)
end

--[[
    Draws a slot's rig under the spectate outline, one Highlight over the
    model every outlined rig is drawn in, seen through walls in the client
    settings' spectate.outline, or back out of it. A body is never outlined
--]]

function Rigs.outline(self: Self, slot: number, outlined: boolean)
	local entry: Entry = self:_entry(slot, "outline")
	if type(outlined) ~= "boolean" then
		error(`Rigs.outline takes outlined as a boolean, not a {typeof(outlined)}`, 2)
	elseif outlined and self._settings.spectate == nil then
		error("Rigs.outline needs the client settings' spectate.outline, and the pool was given none", 2)
	elseif entry.outlined == outlined or entry.body then
		return
	end

	entry.outlined = outlined
	if entry.drawn then
		entry.rig.Parent = self:_holder(entry)
	end
end

-- What a drawn rig is parented to: the outlined model while it is outlined, the pool's folder otherwise
function Rigs._holder(self: Self, entry: Entry): Instance
	if not entry.outlined then
		return self._folder
	end

	local container: Model? = self._container
	if container then
		return container
	end

	-- One Highlight over a model, since Roblox is reported to draw only so many at once. Outline has checked
	-- the pool was given its settings
	local outline: index<Spectate, "outline"> = (self._settings.spectate :: Spectate).outline
	local made: Model = Instance.new("Model")
	made.Name = OUTLINED

	local highlight: Highlight = Instance.new("Highlight")
	highlight.Adornee = made
	highlight.DepthMode = THROUGH_WALLS
	highlight.FillColor = outline.fill
	highlight.FillTransparency = outline.fillTransparency
	highlight.OutlineColor = outline.outline
	highlight.OutlineTransparency = outline.outlineTransparency
	highlight.Parent = made

	made.Parent = self._folder
	self._container = made

	return made
end

--[[
    Shows or hides part of the local player's own body on this screen: the
    first-person copy's arms or chest, the whole copy, or the world rig,
    each setting kept from one body to the next
--]]

function Rigs.show(self: Self, part: FirstPerson.Part, shown: boolean)
	local problem: string? = FirstPerson.refuse(part, shown)
	if problem then
		error(`Rigs.show {problem}`, 2)
	end

	self._firstPerson:show(part, shown)
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
	self._own = nil
	self._copy = nil
	self._folder:Destroy()
end

export type Rigs = Self
type Self = typeof(setmetatable({} :: Fields, Rigs))

return Rigs
