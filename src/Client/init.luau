--[[
    Tread's client handle: the entry a game's client starts once, wiring the
    owner's prediction, the remote interpolation and the rig pool to Tread's
    own Volt scope, and the Client a game holds
--]]

--!strict
local Client = {}
Client.__index = Client

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Block = require(script.Parent.Codec.Block)
local Config = require(script.Parent.Config)
local Engine = require(script.Parent.Step.Engine)
local Fields = require(script.Parent.Codec.Fields)
local Interpolate = require(script.Interpolate)
local Move = require(script.Parent.Codec.Move)
local Predict = require(script.Predict)
local Public = require(script.Parent.Step.Public)
local Record = require(script.Parent.Codec.Record)
local Reliable = require(script.Parent.Codec.Reliable)
local Rigs = require(script.Rigs)
local State = require(script.Parent.Step.State)
local Types = require(script.Parent.Types)
local World = require(script.Parent.Step.World)

local AHEAD: vector = vector.create(0, 0, -1) -- The look before the owner has a body, along -Z as a yaw of 0 looks

-- The frame's render step runs just ahead of a camera bound at Camera priority, and Roblox runs every render step
-- before any PreRender connection, so a camera in either place reads this frame's eye
local FRAME_PRIORITY: number = Enum.RenderPriority.Camera.Value - 1

type ClientSettings = Config.ClientSettings
type Collision = State.Collision
type Footstep = Types.Footstep
type Kind = Block.Kind
type PublicState = Public.State
type Shared = Config.Shared
type Slot = Types.Slot
type StepState = State.State
type Values = State.Values
type World = State.World

type Spawned = (slot: Slot, rig: Model) -> ()
type Despawned = (slot: Slot) -> ()
type Marker = (slot: Slot, marker: string, value: string) -> ()
type Heard = (step: Footstep) -> ()
type Corrected = (size: number, flagged: boolean) -> ()

type Fields = {
	_player: Player,
	_hash: number, -- The shared table's hash, which the server's handshake must match
	_verified: boolean, -- Whether the server's hash matched, before which no OwnerState or relay block is read
	_refused: boolean, -- Whether it didn't, after which the client reads and sends nothing more
	_world: World,
	_rigs: Rigs.Rigs,
	_own: number?, -- The local player's slot, nil while it has none
	_generation: number, -- That slot's generation
	_outfit: Values?, -- Its look and held item, as the relay last gave them, for its rig
	_held: Values?,
	_rigged: { [number]: Slot }, -- Every slot with a rig out, ragdolls included
	_models: { [number]: Model },
	_ragdolls: { [number]: number }, -- Each ragdoll's body slot and the body's generation, which the slot table ends
	_posed: { number }, -- The slots posed each frame: every rigged one but a ragdoll
	_states: { [number]: StepState }, -- Each remote slot's drawn state, refilled each frame
	_bodies: { StepState }, -- The live players and NPCs drawn this frame, which the owner's prediction blocks against
	_eye: vector, -- The owner's eye and look as last drawn, which stay while it has no body
	_look: vector,
	_public: PublicState,
	_spawned: { [{ nil }]: Spawned },
	_despawned: { [{ nil }]: Despawned },
	_heard: { [{ nil }]: Heard },
}

local Started: boolean = false

-- Runs where a game callback's error was raised, so its warning keeps the callback's stack
local function warnCallback(message: unknown)
	warn(`A client callback threw, and the other callbacks still ran: {debug.traceback(tostring(message), 2)}`)
end

-- Runs where one of the game's rig hooks raised an error, so its warning keeps the hook's stack
local function warnHook(message: unknown)
	warn(`A rig hook threw, and the client carried on without it: {debug.traceback(tostring(message), 2)}`)
end

-- Runs where the owner's frame raised an error, a game hook's in it included, so its warning keeps the stack
local function warnFrame(message: unknown)
	warn(`The owner's prediction threw this frame, and the rest still drew: {debug.traceback(tostring(message), 2)}`)
end

--[[
    Tells every callback of a signal, each under its own xpcall, so one
    that throws is warned with its stack and stops neither the others nor
    the caller
--]]

local function fire<A...>(listeners: { [{ nil }]: (A...) -> () }, ...: A...)
	-- A copy, so a callback connected mid-fire waits for the next one and one disconnected mid-fire is skipped
	for token: { nil }, callback: (A...) -> () in table.clone(listeners) do
		if listeners[token] then
			xpcall(callback, warnCallback, ...)
		end
	end
end

-- Connects a game callback to a signal, and gives back the closure that disconnects it
local function connect<A...>(listeners: { [{ nil }]: (A...) -> () }, callback: (A...) -> (), member: string): () -> ()
	if type(callback) ~= "function" then
		error(`client:{member} takes a function, not a {typeof(callback)}`, 3)
	end

	local token: { nil } = {}
	listeners[token] = callback

	-- Cleanup
	return function ()
		listeners[token] = nil
	end
end

--[[
    The character draw distance for this device's class: a console's when
    the screen is a television's, a desktop's with no touch or with a
    keyboard, a phone's on a small touch screen and a tablet's on any other
--]]

local function drawDistance(distances: index<ClientSettings, "drawDistance">): number
	if GuiService:IsTenFootInterface() then
		return distances.console
	elseif not UserInputService.TouchEnabled or UserInputService.KeyboardEnabled then
		return distances.desktop
	elseif GuiService.ViewportDisplaySize == Enum.DisplaySize.Small then
		return distances.phone
	end

	return distances.tablet
end

--- Starts Tread's client, once: checks the shared table and the client
--- settings, starts the owner's prediction, the remote interpolation and
--- the rig pool, and connects Tread's own Volt scope, whose handshake goes
--- out at once. It never yields, and the server's hash of its shared table
--- must match this one's before the client reads a character or sends a
--- Move, so a client with other declarations or values never plays.
--- @function start
--- @within Client
--- @client
--- @param shared Shared -- The table both entry points take
--- @param client ClientSettings -- The client's own settings
--- @return Client -- The handle the game holds

function Client.start(shared: Shared, client: ClientSettings): Client
	if Started then
		error("Tread's client starts once a client, and it has already started", 2)
	end

	Config.client(shared, client)
	local layout: Fields.Layout = Fields.compile(shared.fields)

	local player: Player? = Players.LocalPlayer
	if not player then
		error("Tread's client starts on a client, where Players.LocalPlayer is set", 2)
	end

	local collision: Collision = Engine.casts(shared.collision)
	local world: World = World.new(shared.step, shared.rates.simulation, collision, shared.water, shared.rules, false)
	local rigs: Rigs.Rigs = Rigs.new(client, drawDistance(client.drawDistance), collision)

	Started = true

	local limits: { lean: number, headCone: number } = { lean = shared.step.lean, headCone = shared.step.headCone }
	Interpolate.start(client.interpolation, shared.rates, limits, layout)

	local Network = require(script.Parent.Network.Client)

	-- Volt's Move carries the fields as they are, and the scope sends only when it flushes
	local function send(move: Move.Move)
		Network.Move.fire(move.command, move.acknowledged, move.received, move.delay, move.commands)
		Network.flush()
	end

	Predict.start({
		rates = shared.rates,
		ticks = shared.ticks,
		tolerances = shared.tolerances,
		sample = client.sample,
		look = client.look,
		smoothing = client.smoothing,
		delay = Interpolate.delay,
		layout = layout,
	}, world, send, Interpolate.received)

	local handle: Self = setmetatable({
		_player = player,
		_hash = Config.hash(shared),
		_verified = false,
		_refused = false,
		_world = world,
		_rigs = rigs,
		_own = nil :: number?,
		_generation = 0,
		_outfit = nil :: Values?,
		_held = nil :: Values?,
		_rigged = {} :: { [number]: Slot },
		_models = {} :: { [number]: Model },
		_ragdolls = {} :: { [number]: number },
		_posed = {} :: { number },
		_states = {} :: { [number]: StepState },
		_bodies = {} :: { StepState },
		_eye = vector.zero,
		_look = AHEAD,
		_public = Public.new(),
		_spawned = {} :: { [{ nil }]: Spawned },
		_despawned = {} :: { [{ nil }]: Despawned },
		_heard = {} :: { [{ nil }]: Heard },
	}, Client)

	World.setBodies(world, handle._bodies)

	-- Every connection below lives for the client session
	-- Whiteoak TODO: Platform, Spectate, Withheld and Feed get their listeners with step 3's platforms and spectate
	Network.Shared.on(function (hash: number, _: number)
		handle:_handshake(hash)
	end)

	Network.Slots.on(function (entries: { Reliable.Entry })
		handle:_slots(entries)
	end)

	Network.Death.on(function (character: number, body: number, pushX: number, pushY: number, pushZ: number)
		handle:_death(character, body, pushX, pushY, pushZ)
	end)

	Network.Relay.on(function (data: buffer)
		if handle._verified then
			Interpolate.receive(data)
		end
	end)

	Network.Owner.on(function (data: buffer)
		if handle._verified and handle._own ~= nil then
			Predict.receive(data)
		end
	end)

	Interpolate.onReveal(function (slot: number, kind: Kind, occupant: Instance?, outfit: Values, held: Values?)
		handle:_reveal(slot, kind, occupant :: Player?, outfit, held)
	end)

	Interpolate.onHide(function (slot: number)
		handle:_despawn(slot)
	end)

	Interpolate.onDress(function (slot: number, outfit: Values)
		handle:_dress(slot, outfit)
	end)

	Interpolate.onHold(function (slot: number, held: Values?)
		handle:_hold(slot, held)
	end)

	Interpolate.onFootstep(function (step: Block.Footstep)
		handle:_footstep(step)
	end)

	RunService:BindToRenderStep("TreadFrame", FRAME_PRIORITY, function (dt: number)
		handle:_frame(dt)
	end)

	-- The scope's handshake goes out with the first flush
	Network.flush()

	return handle
end

--[[
    Holds the server's hash of its shared table against this one's: a match
    lets the client play, and a mismatch stops it for good, warns with both
    hashes and kicks the local player with them, so a client with other
    declarations or values never plays
--]]

function Client._handshake(self: Self, hash: number)
	if self._refused then
		return
	elseif hash == self._hash then
		self._verified = true
		return
	end

	self._refused = true
	self._verified = false

	local ours: string = `This client's shared settings hash to {self._hash}`
	local message: string = `{ours} and the server's to {hash}, so Tread's client can't play here`
	warn(message)
	self._player:Kick(message)
end

--[[
    Takes the slot table's entries as Volt's Slots sends them: the local
    player's own slot first, ending its body when its slot is freed, given
    to another or replaced, and a ragdoll whose body's slot the table ends,
    then every entry to the remote interpolation
--]]

function Client._slots(self: Self, entries: { Reliable.Entry })
	if self._refused then
		return
	end

	for _, entry: Reliable.Entry in entries do
		local slot: number, generation: number, rig: Reliable.Rig?, player: Instance? = Reliable.read(entry)

		-- A ragdoll's slot keeps no stretch of its own the interpolation would end, so the table ends it here
		local lying: number? = self._ragdolls[slot]
		if lying ~= nil and (rig == nil or generation ~= lying) then
			self:_despawn(slot)
		end

		if rig ~= nil and player == self._player then
			if slot ~= self._own or generation ~= self._generation then
				self:_leave()
				self._own = slot
				self._generation = generation
			end
		elseif slot == self._own then
			self:_leave()
		end
	end

	Interpolate.slots(entries)
end

--[[
    Ends the local player's own body: its prediction goes back to waiting
    for an OwnerState, and its rig, if one is still out for its slot, goes
    back to the pool
--]]

function Client._leave(self: Self)
	local own: number? = self._own
	if own == nil then
		return
	end

	self._own = nil
	self._outfit = nil
	self._held = nil
	Predict.reset()
	self:_despawn(own)
end

--[[
    Takes a death message as Volt's Death sends it. A rig out for the dying
    slot becomes its body's ragdoll, keyed to the body's slot, and a death
    of the local player's own character ends its body
--]]

function Client._death(self: Self, character: number, body: number, pushX: number, pushY: number, pushZ: number)
	if self._refused then
		return
	end

	local slot: number, bodySlot: number, push: vector = Interpolate.death(character, body, pushX, pushY, pushZ)
	local _, bodyGeneration: number = Record.split(body)
	local dying: Slot? = self._rigged[slot]
	local free: boolean = bodySlot == slot or not self._rigged[bodySlot]

	-- Whiteoak TODO: draw the body lying, with no ragdoll, past bodies.radius or bodies.late and for a body first
	-- met by its reveal, once step 3's bodies give the lying pose
	if dying and self._ragdolls[slot] == nil and free then
		local model: Model = self._models[slot]
		self._rigs:ragdoll(slot, bodySlot, push)
		self:_forget(slot)

		local lying: Slot = { id = bodySlot, kind = "Body", player = nil }
		self._rigged[bodySlot] = lying
		self._models[bodySlot] = model
		self._ragdolls[bodySlot] = bodyGeneration

		fire(self._despawned, dying)
		fire(self._spawned, lying, model)
	end

	if slot == self._own then
		self:_leave()
	end
end

--[[
    Draws a slot a reveal starts: a rig out with its look and held item and
    the spawn told, or, for a slot that already has one, as after a change
    of kind or a ragdoll, the kind kept and nothing told again
--]]

function Client._reveal(self: Self, slot: number, kind: Kind, player: Player?, outfit: Values, held: Values?)
	local drawn: Slot? = self._rigged[slot]
	if drawn then
		drawn.kind = kind
		return
	end

	self:_spawn(slot, kind, player, outfit, held)
end

--[[
    Takes a rig out of the pool for a slot, dressed and holding its item,
    and tells the spawn. A dress hook that throws leaves the slot with no
    rig, so its next reveal tries again
--]]

function Client._spawn(self: Self, slot: number, kind: Kind, player: Player?, outfit: Values, held: Values?)
	local rigs: Rigs.Rigs = self._rigs
	local checked: boolean, rig: Model? = xpcall(rigs.checkout, warnHook, rigs, slot, outfit)
	if not checked or not rig then
		return
	end

	if held then
		xpcall(rigs.hold, warnHook, rigs, slot, held)
	end

	local drawn: Slot = { id = slot, kind = kind, player = player }
	self._rigged[slot] = drawn
	self._models[slot] = rig
	table.insert(self._posed, slot)

	if slot ~= self._own and not self._states[slot] then
		self._states[slot] = State.new()
	end

	fire(self._spawned, drawn, rig)
end

-- Drops a slot's rig from what the handle draws, leaving the pool's own bookkeeping to its caller
function Client._forget(self: Self, slot: number)
	self._rigged[slot] = nil
	self._models[slot] = nil
	self._ragdolls[slot] = nil

	local posed: { number } = self._posed
	local index: number? = table.find(posed, slot)
	if index then
		posed[index] = posed[#posed]
		table.remove(posed)
	end
end

--[[
    Puts a slot's rig back in the pool, a ragdoll's destroyed, and tells
    the despawn. A slot with no rig out changes nothing
--]]

function Client._despawn(self: Self, slot: number)
	local drawn: Slot? = self._rigged[slot]
	if not drawn then
		return
	end

	local rigs: Rigs.Rigs = self._rigs
	xpcall(rigs.release, warnHook, rigs, slot)
	self:_forget(slot)

	fire(self._despawned, drawn)
end

-- A slot's new look on its rig, kept for the local player's own rig until its body has one
function Client._dress(self: Self, slot: number, outfit: Values)
	if slot == self._own then
		self._outfit = outfit
	end

	-- Whiteoak TODO: dress the owner's first-person copy too, once Rigs/FirstPerson.luau builds it
	if self._rigged[slot] then
		local rigs: Rigs.Rigs = self._rigs
		xpcall(rigs.dress, warnHook, rigs, slot, outfit)
	end
end

-- A slot's new held item on its rig, nil for none, kept for the local player's own rig as its look is
function Client._hold(self: Self, slot: number, held: Values?)
	if slot == self._own then
		self._held = held
	end

	-- Whiteoak TODO: hold the item on the owner's first-person copy too, once Rigs/FirstPerson.luau builds it
	if self._rigged[slot] then
		local rigs: Rigs.Rigs = self._rigs
		xpcall(rigs.hold, warnHook, rigs, slot, held)
	end
end

-- Hands each footstep callback its own copy of a step, whose table the interpolation refills, crossed onto Vector3
function Client._footstep(self: Self, step: Block.Footstep)
	if next(self._heard) == nil then
		return
	end

	local heard: Footstep = { at = Engine.toVector3(step.at), kind = step.kind, material = step.material }
	fire(self._heard, heard)
end

--[[
    One rendered frame: the owner's tick and Move, the render clock, the
    owner's own rig out once its body starts, then every drawn rig posed at
    its distance from the owner's eye, and the live players and NPCs drawn
    handed to the owner's prediction to block against. Nothing in the walk
    over the drawn rigs makes a table
--]]

function Client._frame(self: Self, dt: number)
	if self._refused then
		return
	end

	xpcall(Predict.frame, warnFrame, dt)
	Interpolate.frame(dt)

	local own: number? = self._own
	local body: StepState? = Predict.state()
	if body then
		self._eye, self._look = Predict.eye()

		if own ~= nil and not self._rigged[own] then
			self:_spawn(own, "Player", self._player, self._outfit or {}, self._held)
		end
	end

	local rigs: Rigs.Rigs = self._rigs
	local eye: vector = self._eye
	local bodies: { StepState } = self._bodies
	table.clear(bodies)

	for _, slot: number in self._posed do
		if slot == own then
			if body then
				-- The owner's aim pitch from the look it publishes, since its state holds none
				local pitch: number = math.asin(math.clamp(self._look.y, -1, 1))
				rigs:pose(slot, body, vector.magnitude(body.position - eye), pitch)
			end

			continue
		end

		local state: StepState = self._states[slot]
		local drawn: boolean, pitch: number = Interpolate.pose(slot, state)
		if not drawn then
			continue
		end

		rigs:pose(slot, state, vector.magnitude(state.position - eye), pitch)

		local kind: Kind = self._rigged[slot].kind
		if kind == "Player" or kind == "Npc" then
			table.insert(bodies, state)
		end
	end
end

--- The cleared eye and look of what the client views: the owner's own body
--- as drawn this frame, or where it was last drawn while it has none. Tread
--- draws each frame in a render step just ahead of Camera priority, so a
--- camera bound at Camera priority or later, or connected to PreRender,
--- reads this frame's eye.
--- @method getEye
--- @within Client
--- @return Vector3 -- The cleared eye
--- @return Vector3 -- The look, a unit vector

function Client.getEye(self: Self): (Vector3, Vector3)
	if Predict.state() then
		self._eye, self._look = Predict.eye()
	end

	return Engine.toVector3(self._eye), Engine.toVector3(self._look)
end

--- The local character's state as drawn this frame, the same table until
--- the next call, or nil while it has no body.
--- @method getState
--- @within Client
--- @return State? -- Its state, or nil

function Client.getState(self: Self): PublicState?
	local body: StepState? = Predict.state()
	if not body then
		return nil
	end

	local eye: vector, look: vector = Predict.eye()
	Public.fill(self._public, body, self._world, eye, look)

	return self._public
end

--- The render time remote characters are drawn at, in relay ticks with its
--- fraction, which a game stamps on a shot.
--- @method getRenderTime
--- @within Client
--- @return number -- Relay ticks

function Client.getRenderTime(self: Self): number
	return Interpolate.renderTime()
end

--- Registers a ladder for the owner's prediction, as the server registers
--- the same one.
--- @method addLadder
--- @within Client
--- @param cframe CFrame -- The ladder's box, turned as it stands
--- @param size Vector3 -- Its full size along that CFrame's axes
--- @return () -> () -- The closure that removes it

function Client.addLadder(self: Self, cframe: CFrame, size: Vector3): () -> ()
	if typeof(cframe) ~= "CFrame" or typeof(size) ~= "Vector3" then
		error(`client:addLadder takes a CFrame and a Vector3, not a {typeof(cframe)} and a {typeof(size)}`, 2)
	end

	return World.addLadder(self._world, cframe, size)
end

--- Calls back on every replay of the owner's prediction, with the
--- correction's size in studs and whether grounded, posture, mode or the
--- ridden platform flipped.
--- @method onCorrected
--- @within Client
--- @param callback (size: number, flagged: boolean) -> ()
--- @return () -> () -- The closure that disconnects it

function Client.onCorrected(self: Self, callback: Corrected): () -> ()
	if type(callback) ~= "function" then
		error(`client:onCorrected takes a function, not a {typeof(callback)}`, 2)
	end

	return Predict.onCorrected(callback)
end

--- Calls back on every animation marker a drawn rig's track reaches, with
--- its slot, the marker's name and its value.
--- @method onMarker
--- @within Client
--- @param callback (slot: Slot, marker: string, value: string) -> ()
--- @return () -> () -- The closure that disconnects it

function Client.onMarker(self: Self, callback: Marker): () -> ()
	if type(callback) ~= "function" then
		error(`client:onMarker takes a function, not a {typeof(callback)}`, 2)
	end

	return self._rigs:onMarker(function (slot: number, marker: string, value: string)
		local drawn: Slot? = self._rigged[slot]
		if drawn then
			callback(drawn, marker, value)
		end
	end)
end

--- Calls back on each step a culled enemy the viewer can hear takes, with
--- the step's own copy: where it fell, its kind and the ground's material.
--- @method onFootstep
--- @within Client
--- @param callback (step: Footstep) -> ()
--- @return () -> () -- The closure that disconnects it

function Client.onFootstep(self: Self, callback: Heard): () -> ()
	return connect(self._heard, callback, "onFootstep")
end

--- Calls back when a slot's rig is drawn: a character, sleeper or body
--- revealed, the owner's own body started, or a dying rig turned into its
--- body's ragdoll.
--- @method onSpawned
--- @within Client
--- @param callback (slot: Slot, rig: Model) -> ()
--- @return () -> () -- The closure that disconnects it

function Client.onSpawned(self: Self, callback: Spawned): () -> ()
	return connect(self._spawned, callback, "onSpawned")
end

--- Calls back when a slot's rig is put away: hidden, its slot freed or
--- given a new life, or turned into its body's ragdoll.
--- @method onDespawned
--- @within Client
--- @param callback (slot: Slot) -> ()
--- @return () -> () -- The closure that disconnects it

function Client.onDespawned(self: Self, callback: Despawned): () -> ()
	return connect(self._despawned, callback, "onDespawned")
end

--- @class Client
--- The client handle a game holds once Tread's client has started: the
--- eye, the state, the render time, ladders and the client's signals.

export type Client = Self
type Self = typeof(setmetatable({} :: Fields, Client))

return Client
