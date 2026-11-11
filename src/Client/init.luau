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
local ClientPlatforms = require(script.Platforms)
local Config = require(script.Parent.Config)
local Engine = require(script.Parent.Step.Engine)
local Eye = require(script.Parent.Step.Eye)
local Feed = require(script.Parent.Codec.Feed)
local Fields = require(script.Parent.Codec.Fields)
local FirstPerson = require(script.Rigs.FirstPerson)
local Interpolate = require(script.Interpolate)
local Math = require(script.Parent.Step.Math)
local Move = require(script.Parent.Codec.Move)
local OwnerState = require(script.Parent.Codec.OwnerState)
local Platforms = require(script.Parent.Step.Platforms)
local Playback = require(script.Playback)
local Predict = require(script.Predict)
local Public = require(script.Parent.Step.Public)
local Record = require(script.Parent.Codec.Record)
local Reliable = require(script.Parent.Codec.Reliable)
local Rigs = require(script.Rigs)
local Sequence = require(script.Parent.Codec.Sequence)
local State = require(script.Parent.Step.State)
local Types = require(script.Parent.Types)
local World = require(script.Parent.Step.World)

local AHEAD: vector = vector.create(0, 0, -1) -- The look before the owner has a body, along -Z as a yaw of 0 looks
local WIRE: number = 2 ^ 16 -- The values a u16 wire tick holds
local FARTHEST_VIEW: number = WIRE - 1 -- The farthest render distance View's u16 carries, in whole studs
local CALLS_KEPT: number = 2 -- A platform's calls its path runs from, the latest and the one before

-- The frame's render step runs just ahead of a camera bound at Camera priority, and Roblox runs every render step
-- before any PreRender connection, so a camera in either place reads this frame's eye
local FRAME_PRIORITY: number = Enum.RenderPriority.Camera.Value - 1

type ClientSettings = Config.ClientSettings
type Collision = State.Collision
type Footstep = Types.Footstep
type Kind = Block.Kind
type Part = FirstPerson.Part
type Platform = State.Platform
type Playback = Playback.Playback
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

-- The lean and head cone a feed's OwnerState and looks step to
type Limits = { lean: number, headCone: number }

-- A spectate's target as the moderator draws it, from the last two OwnerStates its feed brought
type Watch = {
	slot: number,
	generation: number,
	states: number, -- The feed states held, up to two
	older: StepState,
	newer: StepState,
	spare: StepState, -- What the next feed is read into
	drawn: StepState, -- Between the two, as the last frame or eye drew it
	tick: number, -- The u16 tick with its fraction it was drawn at
	arrived: number, -- The handle's clock when the newer came
	yaw: number, -- The newest stepped command's base look, radians, and head offset, degrees
	pitch: number,
	headYaw: number,
	headPitch: number,
	rig: Model?, -- The rig the pool was last told is the target's
	died: boolean, -- Whether its death came, after which its rig is the body's and none is drawn for it
}

type Fields = {
	_player: Player,
	_hash: number, -- The shared table's hash, which the server's handshake must match
	_verified: boolean, -- Whether the server's hash matched, before which no OwnerState or relay block is read
	_refused: boolean, -- Whether it didn't, after which the client reads and sends nothing more
	_world: World,
	_collision: Collision, -- The step's casts with no platform in them, which a playback's own world wraps
	_rigs: Rigs.Rigs,
	_renderDistance: number, -- Studs this client draws characters to, and asks the server to send them to
	_sendView: (distance: number) -> (), -- Hands View its distance, to go at the next flush
	_layout: Fields.Layout, -- The game's declarations, compiled
	_rates: Playback.Rates, -- The shared table's rates
	_simulation: number, -- The shared table's simulation rate, which an OwnerState's ticks count in
	_limits: Limits,
	_radius: number, -- The client settings' bodies.radius and bodies.late, past which a death draws its body lying
	_late: number,
	_own: number?, -- The local player's slot, nil while it has none
	_generation: number, -- That slot's generation
	_outfit: Values?, -- Its look and held item, as the relay last gave them, for its rig
	_held: Values?,
	_rigged: { [number]: Slot }, -- Every slot with a rig out, bodies included
	_models: { [number]: Model },
	_deaths: { [number]: number }, -- Each body a death drew and the body's generation, which the slot table ends
	_posed: { number }, -- The slots posed each frame: every rigged one but a ragdoll
	_outlined: { [number]: true }, -- The slots whose rigs are drawn under the spectate outline
	_states: { [number]: StepState }, -- Each remote slot's drawn state, refilled each frame
	_bodies: { StepState }, -- The live players and NPCs drawn this frame, which the owner's prediction blocks against
	_eye: vector, -- The eye and look as last drawn, the owner's or a spectated target's, which stay while it has none
	_look: vector,
	_clock: number, -- Seconds the frames have advanced
	_ticks: number?, -- The server's simulation tick unwrapped with its fraction, nil until the handshake names it
	_calls: { [number]: { number } }, -- Each platform's calls heard, by id, the latest two oldest first
	_platforms: { [number]: Platform }, -- Each platform registered on the client, by id, which a playback registers again
	_playback: Playback?, -- The clip playing, nil while none is, during which no live rig is drawn
	_watching: Watch?, -- The spectated target, nil while the client spectates none
	_feedRead: Feed.Feed, -- What each feed is read into
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
	local renderDistance: number = drawDistance(client.drawDistance)
	local rigs: Rigs.Rigs = Rigs.new(client, renderDistance, collision, world)

	Started = true

	local limits: Limits = { lean = shared.step.lean, headCone = shared.step.headCone }
	Interpolate.start(client.interpolation, shared.rates, limits, layout, world)

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
		_collision = collision,
		_rigs = rigs,
		_renderDistance = renderDistance,
		_sendView = Network.View.fire,
		_layout = layout,
		_rates = shared.rates,
		_simulation = shared.rates.simulation,
		_limits = limits,
		_radius = client.bodies.radius,
		_late = client.bodies.late,
		_own = nil :: number?,
		_generation = 0,
		_outfit = nil :: Values?,
		_held = nil :: Values?,
		_rigged = {} :: { [number]: Slot },
		_models = {} :: { [number]: Model },
		_deaths = {} :: { [number]: number },
		_posed = {} :: { number },
		_outlined = {} :: { [number]: true },
		_states = {} :: { [number]: StepState },
		_bodies = {} :: { StepState },
		_eye = vector.zero,
		_look = AHEAD,
		_clock = 0,
		_ticks = nil :: number?,
		_calls = {} :: { [number]: { number } },
		_platforms = {} :: { [number]: Platform },
		_playback = nil :: Playback?,
		_watching = nil :: Watch?,
		_feedRead = Feed.new(),
		_public = Public.new(),
		_spawned = {} :: { [{ nil }]: Spawned },
		_despawned = {} :: { [{ nil }]: Despawned },
		_heard = {} :: { [{ nil }]: Heard },
	}, Client)

	World.setBodies(world, handle._bodies)

	-- Every connection below lives for the client session
	Network.Shared.on(function (hash: number, tick: number)
		handle:_handshake(hash, tick)
	end)

	Network.Platform.on(function (id: number, tick: number)
		handle:_call(id, tick)
	end)

	Network.Gravity.on(function (gravity: number, tick: number)
		handle:_gravity(gravity, tick)
	end)

	Network.Slots.on(function (entries: { Reliable.Entry })
		handle:_slots(entries)
	end)

	Network.Death.on(function (character: number, body: number, pushX: number, pushY: number, pushZ: number)
		handle:_death(character, body, pushX, pushY, pushZ)
	end)

	Network.Spectate.on(function (target: number?, tick: number)
		handle:_spectate(target, tick)
	end)

	Network.Relay.on(function (data: buffer)
		if handle._verified then
			Interpolate.receive(data)
		end
	end)

	Network.Withheld.on(function (data: buffer)
		if handle._verified then
			Interpolate.withheld(data)
		end
	end)

	Network.Owner.on(function (data: buffer)
		if handle._verified and handle._own ~= nil then
			Predict.receive(data)
		end
	end)

	Network.Feed.on(function (data: buffer)
		if handle._verified then
			handle:_feed(data)
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
    lets the client play and starts the clock at the server's tick, and a
    mismatch stops it for good, warns with both hashes and kicks the local
    player with them, so a client with other declarations or values never
    plays

    @ tick | the server's simulation tick, unwrapped from its start
--]]

function Client._handshake(self: Self, hash: number, tick: number)
	if self._refused then
		return
	elseif hash == self._hash then
		self._verified = true

		-- What every later u16 tick unwraps against, a step's included
		self._ticks = tick
		self._world.clock = tick
		self:_announce()

		return
	end

	self._refused = true
	self._verified = false

	local ours: string = `This client's shared settings hash to {self._hash}`
	local message: string = `{ours} and the server's to {hash}, so Tread's client can't play here`
	warn(message)
	self._player:Kick(message)
end

-- Tells the server the render distance, rounded up to whole studs and held to what View carries, at the next flush
function Client._announce(self: Self)
	self._sendView(math.min(math.ceil(self._renderDistance), FARTHEST_VIEW))
end

--[[
    Takes a platform's call as Volt's Platform sends it, applied at once to
    a platform registered now, and kept with the call before it, as the
    step keeps them, for one the game registers later or again

    @ tick | the press's simulation tick, unwrapped from the server's start
--]]

function Client._call(self: Self, id: number, tick: number)
	if self._refused then
		return
	end

	local calls: { number } = self._calls[id] or {}
	self._calls[id] = calls
	if table.find(calls, tick) then
		return
	end

	table.insert(calls, tick)
	table.sort(calls)
	if #calls > CALLS_KEPT then
		table.remove(calls, 1)
	end

	local world: World = self._world
	if world.platforms[id] ~= nil then
		Platforms.call(world, id, tick)
	end
end

--[[
    Takes a gravity change as Volt's Gravity sends it, applied at once: the
    owner's prediction and replays step its tick and later under it, and
    every sleeper's fall is drawn under it from its tick. A body in the air
    at the change gets one correction from the server's next state

    @ tick | the simulation tick it applies from, unwrapped from the server's start
--]]

function Client._gravity(self: Self, gravity: number, tick: number)
	if self._refused then
		return
	end

	World.setGravity(self._world, gravity, tick)
end

--[[
    Takes the slot table's entries as Volt's Slots sends them: the local
    player's own slot first, ending its body when its slot is freed, given
    to another or replaced, and a body a death drew whose slot the table
    ends, then every entry to the remote interpolation
--]]

function Client._slots(self: Self, entries: { Reliable.Entry })
	if self._refused then
		return
	end

	for _, entry: Reliable.Entry in entries do
		local slot: number, generation: number, rig: Reliable.Rig?, player: Instance? = Reliable.read(entry)

		-- A body a death drew may have no stretch of its own the interpolation would end, so the table ends it here
		local lying: number? = self._deaths[slot]
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
    slot becomes its body's, keyed to the body's slot, and a death of the
    local player's own character ends its body
--]]

function Client._death(self: Self, character: number, body: number, pushX: number, pushY: number, pushZ: number)
	if self._refused then
		return
	end

	local slot: number, bodySlot: number, push: vector, age: number =
		Interpolate.death(character, body, pushX, pushY, pushZ)
	local _, bodyGeneration: number = Record.split(body)
	local dying: Slot? = self._rigged[slot]

	if dying and self._deaths[slot] == nil then
		-- A body its own reveal drew before the death came gives its rig back for the one that died, which would
		-- otherwise stay out with nothing to pose it
		if bodySlot ~= slot and self._rigged[bodySlot] then
			self:_despawn(bodySlot)
		end

		self:_bury(dying, slot, bodySlot, bodyGeneration, push, age)
	end

	local watching: Watch? = self._watching
	if watching and slot == watching.slot then
		watching.died = true
	end

	if slot == self._own then
		self:_leave()
	end
end

--[[
    Turns a dying slot's rig into its body's, keyed to the body's slot: a
    ragdoll pushed along the death's attack for a client within
    bodies.radius of where it was drawn, which the death reached within
    bodies.late of its newest record, and otherwise laid down at once where
    it was drawn. The owner's own body and a spectated target are drawn
    from states the server sends live, so their deaths are never late

    @ age | seconds since the dying life's newest record, by the clock's estimate
--]]

function Client._bury(
	self: Self,
	dying: Slot,
	slot: number,
	body: number,
	generation: number,
	push: vector,
	age: number
)
	local watching: Watch? = self._watching
	local from: StepState? = self._states[slot]
	local late: number = age

	if slot == self._own then
		from = Predict.state()
		late = 0
	elseif watching and slot == watching.slot then
		from = nil
		if watching.states > 0 then
			from = watching.drawn
		end
		late = 0
	end

	local distance: number = math.huge
	if from then
		distance = vector.magnitude(from.position - self._eye)
	end

	local rigs: Rigs.Rigs = self._rigs
	local model: Model = self._models[slot]
	local ragdolls: boolean = distance <= self._radius and late <= self._late

	if ragdolls then
		rigs:ragdoll(slot, body, push)
	else
		rigs:lie(slot, body)
	end

	self:_forget(slot)

	local lying: Slot = { id = body, kind = "Body", player = nil, withheld = false }
	self._rigged[body] = lying
	self._models[body] = model
	self._deaths[body] = generation

	-- A body laid down is posed with every other rig, lying where the dying rig was drawn until its own records come
	if not ragdolls then
		table.insert(self._posed, body)

		local state: StepState = self._states[body] or State.new()
		self._states[body] = state

		if from then
			State.copy(from, state)
			Interpolate.lying(state)
			rigs:pose(body, state, distance, 0)
		end
	end

	fire(self._despawned, dying)
	fire(self._spawned, lying, model)
end

--[[
    Takes a spectate's start, switch or end as Volt's Spectate sends it:
    the characters drawn from before the new view's first tick close, the
    old target's rig goes back to the pool, and a new target is drawn from
    its feed from then on, its world rig taking the local player's own rig
    setting on this screen
--]]

function Client._spectate(self: Self, target: number?, tick: number)
	if self._refused then
		return
	end

	Interpolate.restart(tick)

	local watching: Watch? = self._watching
	if watching then
		self._watching = nil
		self:_despawn(watching.slot)
	end

	if target == nil then
		return
	end

	local slot: number, generation: number = Record.split(target)
	self._watching = {
		slot = slot,
		generation = generation,
		states = 0,
		older = State.new(),
		newer = State.new(),
		spare = State.new(),
		drawn = State.new(),
		tick = 0,
		arrived = 0,
		yaw = 0,
		pitch = 0,
		headYaw = 0,
		headPitch = 0,
		rig = nil,
		died = false,
	}
end

--[[
    Takes one feed as Volt's Feed sends it while the client spectates: the
    target's OwnerState becomes the newer of the two it is drawn between,
    one no newer than that is a straggler and dropped, and the newest
    stepped command's look is the one its eye looks along
--]]

function Client._feed(self: Self, data: buffer)
	local watching: Watch? = self._watching
	if not watching then
		return
	end

	local feed: Feed.Feed = self._feedRead
	Feed.read(data, feed, self._limits)

	local spare: StepState = watching.spare
	OwnerState.read(feed.ownerData, feed.ownerAt, feed.ownerLength, spare, nil, self._limits)

	if watching.states > 0 and Sequence.difference(spare.tick, watching.newer.tick) <= 0 then
		return
	end

	watching.spare = watching.older
	watching.older = watching.newer
	watching.newer = spare
	watching.states = math.min(watching.states + 1, 2)
	watching.arrived = self._clock

	if feed.count > 0 then
		local look: Feed.Look = feed.looks[1]
		watching.yaw = look.yaw
		watching.pitch = look.pitch
		watching.headYaw = look.headYaw
		watching.headPitch = look.headPitch
	end
end

--[[
    The spectated target as drawn now, between its last two feed states
    over the ticks between them from the newer's arrival on, never across
    a teleport or a change of platform, with the tick it is drawn at, and
    its cleared eye and newest look made the eye the client views; nil
    before its first feed. It makes no table
--]]

function Client._view(self: Self): StepState?
	local watching: Watch? = self._watching
	if not watching or watching.states == 0 then
		return nil
	end

	local drawn: StepState = watching.drawn
	local older: StepState = watching.older
	local newer: StepState = watching.newer

	local t: number = 1
	if watching.states > 1 then
		local span: number = Sequence.difference(newer.tick, older.tick) / self._simulation
		t = math.clamp((self._clock - watching.arrived) / span, 0, 1)
	end

	-- The tick goes with the share the state was drawn at, the older's while it holds and the newer's from its time on
	local share: number = Playback.between(older, newer, t, drawn)
	local fromTick: number = older.tick
	watching.tick = Math.lerp(fromTick, fromTick + Sequence.difference(newer.tick, fromTick), share) % WIRE

	local world: World = self._world
	self._eye = Eye.clear(drawn, world)
	self._look =
		Public.look(watching.yaw, watching.pitch, watching.headYaw, watching.headPitch, world.settings.headCone)

	return drawn
end

--[[
    Takes the spectated target's rig out once its first feed has come,
    dressed as the look entries last gave it, and tells the pool it is the
    target's, whose world rig takes the local player's own rig setting
--]]

function Client._watch(self: Self, watching: Watch)
	local slot: number = watching.slot
	if not self._rigged[slot] then
		local occupant: Instance?, outfit: Values, held: Values? = Interpolate.occupant(slot)
		self:_spawn(slot, "Player", occupant :: Player?, outfit, held)
	end

	local model: Model? = self._models[slot]
	if model and model ~= watching.rig then
		watching.rig = model
		self._rigs:watch(slot)
	end
end

--[[
    Draws a slot a reveal starts: a rig out with its look and held item and
    the spawn told, or, for a slot that already has one, as after a change
    of kind or a death, the kind kept and nothing told again
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
    and tells the spawn. The local player's own rig comes out with its
    first-person copy, and is hidden on their screen. A dress hook that
    throws leaves the slot with no rig, so its next reveal tries again.
    While a playback runs no live rig comes out, and its end draws again
    every live stretch still open
--]]

function Client._spawn(self: Self, slot: number, kind: Kind, player: Player?, outfit: Values, held: Values?)
	if self._playback then
		return
	end

	local rigs: Rigs.Rigs = self._rigs
	local own: boolean = slot == self._own
	local checked: boolean, rig: Model? = xpcall(rigs.checkout, warnHook, rigs, slot, outfit, own)
	if not checked or not rig then
		return
	end

	if held then
		xpcall(rigs.hold, warnHook, rigs, slot, held)
	end

	local drawn: Slot = { id = slot, kind = kind, player = player, withheld = Interpolate.isWithheld(slot) }
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
	self._deaths[slot] = nil
	self._outlined[slot] = nil

	local watching: Watch? = self._watching
	if watching and slot == watching.slot then
		watching.rig = nil
	end

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

	-- The pool dresses the local player's own first-person copy with their world rig
	if self._rigged[slot] then
		local rigs: Rigs.Rigs = self._rigs
		xpcall(rigs.dress, warnHook, rigs, slot, outfit)
	end
end

--[[
    A slot's new held item on its rig, nil for none, kept for the local
    player's own rig as its look is, and handed to the owner's prediction,
    whose rules read the item its body holds
--]]

function Client._hold(self: Self, slot: number, held: Values?)
	if slot == self._own then
		self._held = held
		Predict.hold(held)
	end

	-- The pool puts it in the local player's own first-person copy's hands too
	if self._rigged[slot] then
		local rigs: Rigs.Rigs = self._rigs
		xpcall(rigs.hold, warnHook, rigs, slot, held)
	end
end

-- A live footstep, dropped while a playback runs, whose clip raises its own
function Client._footstep(self: Self, step: Block.Footstep)
	if self._playback then
		return
	end

	self:_hear(step)
end

-- Hands each footstep callback its own copy of a step, whose table its reader refills, crossed onto Vector3
function Client._hear(self: Self, step: Block.Footstep)
	if next(self._heard) == nil then
		return
	end

	local heard: Footstep = { at = Engine.toVector3(step.at), kind = step.kind, material = step.material }
	fire(self._heard, heard)
end

-- Draws a slot's rig under the spectate outline or out of it, telling the pool only of a change
function Client._outline(self: Self, slot: number, outlined: boolean)
	if (self._outlined[slot] == true) == outlined then
		return
	end

	if outlined then
		self._outlined[slot] = true
	else
		self._outlined[slot] = nil
	end

	self._rigs:outline(slot, outlined)
end

--[[
    Moves the clock on a frame and places every platform's copy. The clock
    follows the tick the owner's body is drawn at, unwrapped, and runs on at
    the simulation rate while it has none, and the world's clock is its
    floor, so every step and replay unwraps its tick against it. The copies
    stand at the owner's drawn tick, a viewed target's while the client
    spectates, or the clock with no body, and a playback places them
    itself. Before the handshake names the server's tick nothing moves
--]]

function Client._place(self: Self, dt: number, viewed: StepState?)
	local started: number? = self._ticks
	if started == nil then
		return
	end

	local world: World = self._world
	local ticks: number = started
	local drawn: number? = Predict.drawn()

	if drawn ~= nil then
		ticks += Sequence.difference(drawn, ticks % WIRE)
	else
		ticks += dt * self._simulation

		-- With no body nothing steps, so the casts outside the step meet the platforms where the clock stands
		world.tick = math.floor(ticks) % WIRE
	end

	self._ticks = ticks
	world.clock = math.floor(ticks)

	if self._playback then
		return
	end

	local at: number = ticks
	local watching: Watch? = self._watching
	if watching and viewed then
		at = ticks + Sequence.difference(watching.tick, ticks % WIRE)
	end

	ClientPlatforms.frame(world, at)
end

--[[
    One rendered frame: the render clock, then the owner's tick and Move,
    the owner's own rig and its first-person copy out once its body starts, a
    spectated target drawn from its feed, the clock and the platforms'
    copies, then every drawn rig posed at its distance from the eye viewed,
    a remote rider on its platform's copy, each other player outlined while
    the client spectates, and the live players and NPCs drawn handed to the
    owner's prediction to block against. Nothing in the walk over the drawn
    rigs makes a table. While a playback runs, prediction, the render clock
    and the clock still run on live data, unseen, no live rig is drawn and
    no live body is blocked against, and the playback sets its track speed
--]]

function Client._frame(self: Self, dt: number)
	if self._refused then
		return
	end

	self._clock += dt

	-- The render clock moves first, so this frame's commands claim its render time and their Move reports its delay
	Interpolate.frame(dt)
	xpcall(Predict.frame, warnFrame, dt)

	local playback: Playback? = self._playback
	if playback then
		table.clear(self._bodies)
		self:_place(dt, nil)
		playback:frame(dt)

		return
	end

	local own: number? = self._own
	local body: StepState? = Predict.state()
	if body then
		self._eye, self._look = Predict.eye()

		if own ~= nil and not self._rigged[own] then
			self:_spawn(own, "Player", self._player, self._outfit or {}, self._held)
		end
	end

	-- The owner's aim pitch from the look it publishes, since its state holds none, before a target's eye replaces it
	local ownPitch: number = Playback.pitchOf(self._look)

	local watching: Watch? = self._watching
	local viewed: StepState? = self:_view()
	self:_place(dt, viewed)

	local target: number? = nil
	if watching and viewed and not watching.died then
		target = watching.slot
		self:_watch(watching)
	end

	local rigs: Rigs.Rigs = self._rigs
	local eye: vector = self._eye
	local bodies: { StepState } = self._bodies
	table.clear(bodies)

	for _, slot: number in self._posed do
		if slot == own then
			-- The pool poses the owner's first-person copy behind its world rig with no aim pitch
			if body then
				rigs:pose(slot, body, vector.magnitude(body.position - eye), ownPitch)
			end

			continue
		end

		local drawn: Slot = self._rigged[slot]
		if slot == target and viewed then
			rigs:pose(slot, viewed, vector.magnitude(viewed.position - eye), Playback.pitchOf(self._look))
			table.insert(bodies, viewed)

			continue
		end

		drawn.withheld = Interpolate.isWithheld(slot)
		self:_outline(slot, watching ~= nil and drawn.kind == "Player")

		local state: StepState = self._states[slot]
		local shown: boolean, pitch: number = Interpolate.pose(slot, state)
		if not shown or not Playback.ride(state) then
			continue
		end

		rigs:pose(slot, state, vector.magnitude(state.position - eye), pitch)

		if drawn.kind == "Player" or drawn.kind == "Npc" then
			table.insert(bodies, state)
		end
	end
end

--- The cleared eye and look of what the client views: a playback's
--- target as its last render drew it, a spectated target's from its feed,
--- drawn between its last two states and looking along its newest
--- command's look, else the owner's own body as drawn this frame, or where
--- the eye was last drawn while there is none. Tread draws each frame in a
--- render step just ahead of Camera priority, so a camera bound at Camera
--- priority or later, or connected to PreRender, reads this frame's eye.
--- @method getEye
--- @within Client
--- @return Vector3 -- The cleared eye
--- @return Vector3 -- The look, a unit vector

function Client.getEye(self: Self): (Vector3, Vector3)
	local playback: Playback? = self._playback
	if playback then
		local eye: vector, look: vector = playback:eye()

		return Engine.toVector3(eye), Engine.toVector3(look)
	end

	if self:_view() == nil and Predict.state() then
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
--- fraction, which a game stamps on a shot. Inside the sample it is the
--- render time of the frame being drawn, the same frame whose delay the
--- command's Move reports.
--- @method getRenderTime
--- @within Client
--- @return number -- Relay ticks

function Client.getRenderTime(self: Self): number
	return Interpolate.renderTime()
end

--- Sets how far, in studs, this client draws characters and is sent
--- them, as from a settings menu. It starts at the device class's
--- drawDistance, and the server holds what it is sent to its own
--- relevancy.leave. The server hears it once the handshake passes and
--- again on each call, and drops the calls that come faster than the
--- server settings' rates.view allows, so a game sets it once the player
--- applies the setting. It errors on anything that is not a finite number
--- above 0.
--- @method setRenderDistance
--- @within Client
--- @param studs number -- The render distance

function Client.setRenderDistance(self: Self, studs: number)
	if type(studs) ~= "number" or not (studs > 0 and studs < math.huge) then
		error(`client:setRenderDistance takes a finite number of studs above 0, not {studs}`, 2)
	end

	self._renderDistance = studs
	self._rigs:setDrawDistance(studs)

	if self._verified then
		self:_announce()
	end
end

--- Where the feet would end if jump were pressed now: the point on the
--- ledge's top a mantle from the owner's newest predicted tick would end
--- at, or nil when a press would start none or before the owner has a
--- body, for the game's mantle prompt. It runs the press's own ledge
--- search at most once a predicted tick, and never throws.
--- @method getMantle
--- @within Client
--- @return Vector3? -- Where the feet would end, or nil

function Client.getMantle(self: Self): Vector3?
	local ending: vector? = Predict.mantle()
	if ending == nil then
		return nil
	end

	return Engine.toVector3(ending)
end

--- Shows or hides part of the local player's own body on their own
--- screen: "arms" both arms of the first-person copy, upper arm, lower arm
--- and hand, "chest" its upper torso, "copy" the whole copy, and "rig" the
--- world rig other players see, hidden here until the game shows it, for a
--- camera that leaves the eye. While the client spectates, the target's
--- world rig takes the "rig" setting too. The copy's head always stays out
--- of view. Each setting holds from one body to the next, so a view the
--- game set stays through a respawn.
--- @method showBody
--- @within Client
--- @param part "arms" | "chest" | "copy" | "rig" -- What to show or hide
--- @param shown boolean -- Whether it shows

function Client.showBody(self: Self, part: Part, shown: boolean)
	local problem: string? = FirstPerson.refuse(part, shown)
	if problem then
		error(`client:showBody {problem}`, 2)
	end

	self._rigs:show(part, shown)
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

--- Registers a moving platform for the owner's prediction and this
--- screen, as the server registers the same one: its boxes join the casts
--- prediction steps against where its path puts them, every call already
--- heard for its id applies, and its model, if it has one, moves each
--- frame to where its path puts it at the tick the owner's body is drawn
--- at. It refuses what the server's refuses, and a model part with
--- CanCollide on.
--- @method addPlatform
--- @within Client
--- @param platform Platform -- Its id, its boxes in its own space, its path and its model
--- @return () -> () -- The closure that removes it

function Client.addPlatform(self: Self, platform: Platform): () -> ()
	local world: World = self._world
	local remove: () -> () = ClientPlatforms.add(world, platform)
	local id: number = platform.id
	self._platforms[id] = platform

	local calls: { number }? = self._calls[id]
	if calls then
		for _, tick: number in calls do
			Platforms.call(world, id, tick)
		end
	end

	-- Cleanup
	return function ()
		remove()

		if self._platforms[id] == platform then
			self._platforms[id] = nil
		end
	end
end

--- Plays a moderator's clip as the taps recorded it: its keyframe first,
--- then the target's observed frames from the keyframe's tick on, and
--- optionally the withheld frames over the same ticks. It never yields.
--- Every live rig goes back to the pool while it runs, its rigs come from
--- the client's own pool with slots that name no player, and getEye gives
--- its eye and look, while prediction and the live characters carry on
--- unseen. It errors, changing nothing, while another playback runs, and
--- on a clip this client can't read.
--- @method play
--- @within Client
--- @param ticks { buffer } -- The keyframe, then the observed frames, oldest first
--- @param withheld { buffer }? -- The withheld frames over the same ticks, oldest first
--- @return Playback -- What renders it and ends it

function Client.play(self: Self, ticks: { buffer }, withheld: { buffer }?): Playback
	if self._playback then
		error("client:play plays one clip at a time, and one is playing", 2)
	end

	local platforms: { Platform } = {}
	for _, platform: Platform in self._platforms do
		table.insert(platforms, platform)
	end

	local playback: Playback = Playback.new({
		rigs = self._rigs,
		world = self._world,
		collision = self._collision,
		platforms = platforms,
		clock = self._ticks,
		layout = self._layout,
		limits = self._limits,
		rates = self._rates,
		eye = self._eye,
		look = self._look,

		spawned = function (slot: Slot, rig: Model)
			fire(self._spawned, slot, rig)
		end,

		despawned = function (slot: Slot)
			fire(self._despawned, slot)
		end,

		heard = function (step: Block.Footstep)
			self:_hear(step)
		end,

		ended = function ()
			self:_resume()
		end,
	}, ticks, withheld)

	-- Every live rig goes back to the pool, which holds one a slot, so no live rig is drawn beside the clip's
	for slot: number in table.clone(self._rigged) do
		self:_despawn(slot)
	end

	self._playback = playback

	return playback
end

--[[
    Ends the playback on the live characters: every live stretch still
    open is drawn again, each told to the spawn, while the owner's and the
    spectated target's rigs come back on the next frame as they first did
--]]

function Client._resume(self: Self)
	self._playback = nil

	-- Whiteoak TODO: a body a live death laid down before play has no stretch of its own, so it stays undrawn until
	-- its own reveal; keep each such body's last drawn state through the playback and lay it down again here, once a
	-- moderator's review shows the gap
	Interpolate.revealOpen()
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

--- Calls back on every animation marker a drawn rig's track reaches, a
--- playback's rigs included, with its slot, the marker's name and its
--- value.
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
		local playback: Playback? = self._playback
		if playback then
			drawn = playback:slotOf(slot)
		end

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
--- revealed, the owner's own body started, a spectated target's first
--- feed, or a dying rig turned into its body. While the client spectates,
--- a slot's withheld says whether anti-ESP withheld it from the target.
--- @method onSpawned
--- @within Client
--- @param callback (slot: Slot, rig: Model) -> ()
--- @return () -> () -- The closure that disconnects it

function Client.onSpawned(self: Self, callback: Spawned): () -> ()
	return connect(self._spawned, callback, "onSpawned")
end

--- Calls back when a slot's rig is put away: hidden, its slot freed or
--- given a new life, dropped by a spectate's start or end, or turned into
--- its body.
--- @method onDespawned
--- @within Client
--- @param callback (slot: Slot) -> ()
--- @return () -> () -- The closure that disconnects it

function Client.onDespawned(self: Self, callback: Despawned): () -> ()
	return connect(self._despawned, callback, "onDespawned")
end

--- @class Client
--- The client handle a game holds once Tread's client has started: the
--- eye, the state, the render time and distance, where a mantle would
--- end, the local player's own body on their screen, ladders, platforms,
--- a moderator's clips and the client's signals.

export type Client = Self
type Self = typeof(setmetatable({} :: Fields, Client))

return Client
