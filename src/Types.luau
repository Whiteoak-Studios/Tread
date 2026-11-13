--[[
    The types the handles hand a game, written apart from the realms' own
    modules, so Config and the package root name them and load neither realm
--]]

--!strict
local Block = require(script.Parent.Codec.Block)
local Public = require(script.Parent.Step.Public)
local State = require(script.Parent.Step.State)

type Kind = Block.Kind
type MoveMode = State.MoveMode
type Posture = State.Posture
type PublicState = Public.State
type Step = Block.Step
type Values = State.Values

-- One of Volt's bots, which a character can belong to in place of a Player
export type Bot = { Name: string }

-- What a character holds: whose it is, and the slot and life its methods read and write the server's bodies by
export type CharacterFields = {
	player: Player | Bot,
	_slot: number,
	_generation: number,
	_live: boolean, -- Until it dies, sleeps or is destroyed
	_kept: boolean, -- Whether it still holds its slot, which a sleep hands the sleeper and a destroy releases
	_destroyed: boolean,
}

-- The character's methods, which Characters.luau defines
export type CharacterOwn = {
	getState: (self: Character) -> PublicState,
	setMode: (self: Character, mode: MoveMode) -> (),
	teleport: (self: Character, at: CFrame) -> (),
	setDowned: (self: Character, downed: boolean) -> (),
	setField: (self: Character, name: string, value: number | boolean) -> (),
	setOutfit: (self: Character, outfit: Values) -> (),
	setHeld: (self: Character, held: Values?) -> (),
	setTeam: (self: Character, team: number?) -> (),
	setInvisible: (self: Character, invisible: boolean) -> (),
	sleep: (self: Character) -> Sleeper?,
	die: (self: Character, push: Vector3?) -> Body,
	destroy: (self: Character) -> (),
}

export type Character = CharacterFields & CharacterOwn

-- What a sleeper holds: the slot and life it keeps through a wake, which its methods read and write
export type SleeperFields = {
	_slot: number,
	_generation: number,
	_live: boolean, -- Until it wakes or is destroyed
}

-- The sleeper's methods, which Characters.luau defines
export type SleeperOwn = {
	wake: (self: Sleeper, player: Player | Bot) -> Character,
	moveTo: (self: Sleeper, at: CFrame) -> (),
	destroy: (self: Sleeper) -> (),
}

export type Sleeper = SleeperFields & SleeperOwn

-- What a body holds: its own slot and life, until the game removes it
export type BodyFields = {
	_slot: number,
	_generation: number,
	_live: boolean, -- Until destroy
}

-- The body's one method, which Characters.luau defines
export type BodyOwn = {
	destroy: (self: Body) -> (),
}

export type Body = BodyFields & BodyOwn

-- One capsule of a hit shape: in the character's own space in the shared table's hit shapes, its feet at the origin
-- facing along -Z, and placed in the world in a sample
export type Shape = {
	from: Vector3,
	to: Vector3,
	radius: number,
}

-- A body's place at a render time for a hit test. Each slot keeps one a posture, which its next read of that posture
-- rewrites
export type Sample = {
	epoch: number,
	position: Vector3, -- The feet
	yaw: number, -- Radians
	posture: Posture, -- The posture whose shapes are placed: Crouch for a swimmer
	body: Shape, -- The body capsule, placed in the world
	zones: { [string]: Shape }, -- The zone capsules by name, placed the same way
}

-- A slot a rig is drawn for, as the client's signals hand it: the same table from its spawn to its despawn
export type Slot = {
	id: number,
	kind: Kind, -- Changes in place when a drawn character changes kind, as a player falling asleep does
	player: Player?, -- A live player's, nil for any other kind
	withheld: boolean, -- While a spectating moderator is sent it only because anti-ESP withheld it from the target
}

-- A culled enemy's step the viewer can hear: where it fell, its kind and the ground's material, and no player
export type Footstep = {
	at: Vector3,
	kind: Step,
	material: Enum.Material,
}

-- What a relay tap hands each sink once a relay tick: the relay tick, unwrapped, and that tick's frame in a new
-- buffer the sink may keep and never writes, in the layout Tread.decode reads as a tap
export type Sink = (tick: number, records: buffer) -> ()

-- A taken slot as onReliable reports it: the life it belongs to, its kind and rig mode, and its look and held item
-- as their packed bytes, each empty while none is set, with no player named
export type SlotEntry = {
	generation: number,
	kind: Kind,
	rig: "A" | "B",
	look: buffer,
	held: buffer,
}

-- A death as onReliable reports it: the dying character and its body, each the u16 slot and generation every layout
-- names a character by, and the attack's direction, zero for none
export type Death = {
	character: number,
	body: number,
	push: Vector3,
}

-- One change to the state a snapshot holds, by slot, with its value before and after: a slot taken, changed or
-- freed, nil while free; a look or a held item within one life; or a death, which has nothing before it
export type Change =
	{ slot: number, kind: "slot", previous: SlotEntry?, current: SlotEntry? }
	| { slot: number, kind: "look", previous: buffer, current: buffer }
	| { slot: number, kind: "held", previous: buffer, current: buffer }
	| { slot: number, kind: "death", previous: nil, current: Death }

return {}
