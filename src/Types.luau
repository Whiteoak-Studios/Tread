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
	_live: boolean, -- Until destroy
}

-- The character's methods, which Characters.luau defines
export type CharacterOwn = {
	getState: (self: Character) -> PublicState,
	setMode: (self: Character, mode: MoveMode) -> (),
	setDowned: (self: Character, downed: boolean) -> (),
	setField: (self: Character, name: string, value: number | boolean) -> (),
	setOutfit: (self: Character, outfit: Values) -> (),
	setHeld: (self: Character, held: Values?) -> (),
	setInvisible: (self: Character, invisible: boolean) -> (),
	destroy: (self: Character) -> (),
}

export type Character = CharacterFields & CharacterOwn

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
}

-- A culled enemy's step the viewer can hear: where it fell, its kind and the ground's material, and no player
export type Footstep = {
	at: Vector3,
	kind: Step,
	material: Enum.Material,
}

return {}
