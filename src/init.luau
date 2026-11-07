--[[
    Tread's public API, the one module a game requires: the server's and the
    client's entry points, the codec's version and its decoder, and every
    type a game names
--]]

--!strict
local Config = require(script.Config)
local Constants = require(script.Constants)
local Decode = require(script.Codec.Decode)
local Engine = require(script.Step.Engine)
local Public = require(script.Step.Public)
local State = require(script.Step.State)
local Types = require(script.Types)

export type Shared = Config.Shared
export type ServerSettings = Config.ServerSettings
export type ClientSettings = Config.ClientSettings

-- The handles' own types, read off their constructors inside typeof, which never runs, so neither realm loads here
export type Server = typeof(require(script.Server).start(nil :: any, nil :: any))
export type Client = typeof(require(script.Client).start(nil :: any, nil :: any))
export type Character = Types.Character
export type Npc = typeof(require(script.Server.Characters).createNpc(nil :: any))
export type Target = Character | Npc
export type Bot = Types.Bot

export type State = Public.State
export type Box = Public.Box
export type Command = State.Command
export type RuleStep = State.RuleStep
export type Allow = State.Allow
export type Field = State.Field
export type Fields = State.Fields
export type Hit = State.GameHit
export type Sample = Types.Sample
export type Shape = Types.Shape
export type Outfit = State.Values
export type Held = State.Values
export type Slot = Types.Slot
export type Footstep = Types.Footstep
export type Mode = State.Mode
export type Posture = State.Posture
export type MoveMode = State.MoveMode

--- @class Tread
--- Tread's public API: the server's and the client's entry points, which
--- each check the game's tables and start their realm, and the decoder
--- for clips and tools.

local Tread = {}

--- @prop CODEC_VERSION number
--- @within Tread
--- The version of Tread's own wire layouts, the record, the state word,
--- OwnerState and the command among them, which every keyframe carries.

Tread.CODEC_VERSION = Constants.CODEC_VERSION

--- Starts Tread's server, once a server: checks the shared table and the
--- server settings and errors on the first key missing or wrong, binds
--- Tread's own Volt endpoints at the settings' rates, starts the tick and
--- returns the server handle. It never yields, and only it loads the
--- server's modules, so a client that requires Tread loads none of them.
--- @within Tread
--- @server
--- @param shared Shared -- The table both entry points take
--- @param server ServerSettings -- The server's own settings
--- @return Server -- The handle the game holds

function Tread.startServer(shared: Shared, server: ServerSettings): Server
	local Server = require(script.Server)

	return Server.start(shared, server)
end

--- Starts Tread's client, once a client: checks the shared table and the
--- client settings and errors on the first key missing or wrong, starts
--- the owner's prediction, the remote interpolation and the rig pool, and
--- returns the client handle. It never yields, and only it loads the
--- client's modules, so a server that requires Tread loads none of them.
--- @within Tread
--- @client
--- @param shared Shared -- The table both entry points take
--- @param client ClientSettings -- The client's own settings
--- @return Client -- The handle the game holds

function Tread.startClient(shared: Shared, client: ClientSettings): Client
	-- Whiteoak TODO: error naming Workspace.UseFixedSimulation while it is on, once a live-server run in the dev
	-- experience tells the setting's two states apart, since no script can read it
	local Client = require(script.Client)

	return Client.start(shared, client)
end

-- Every vector in a decoded table and the tables inside it crossed onto Vector3, in place
local function crossed(decoded: { [any]: any }): { [any]: any }
	for key: any, value: any in decoded do
		if type(value) == "vector" then
			decoded[key] = Engine.toVector3(value)
		elseif type(value) == "table" then
			crossed(value)
		end
	end

	return decoded
end

--- Decodes one of Tread's layouts, as a CODEC_VERSION packed it, into new
--- tables, for clips and tools: relay, withheld, owner, feed, keyframe,
--- record or command. Every position and direction comes back a Vector3,
--- and each block of the game's declared fields as its packed bytes. It
--- errors on a version or kind it has no reader for, and on bytes that
--- aren't that layout.
--- @within Tread
--- @param version number -- The CODEC_VERSION the bytes were packed with
--- @param kind string -- The layout's name
--- @param data buffer -- Its bytes
--- @return { [string]: any } -- Its fields by name

function Tread.decode(version: number, kind: string, data: buffer): { [string]: any }
	return crossed(Decode.decode(version, kind, data))
end

return Tread
