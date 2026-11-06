--[[
    The server's connection records, one for each player or bot, which key
    every per-client structure in place of the Player, each with its round
    trip and jitter smoothed from the pings it samples
--]]

--!strict
local Connection = {}
Connection.__index = Connection

type Bot = { Name: string }

type Fields = {
	player: Player | Bot, -- Whose it is: a Player or one of Volt's bots
	_engine: Player?, -- The Player whose engine ping it samples, nil for a bot's
	_sampled: boolean, -- Whether it has sampled a ping yet
	_mean: number, -- The pings' exponentially weighted mean, in seconds
	_variance: number, -- And their weighted variance about it
}

local Records: { [Player | Bot]: Connection } = {}

local Smoothing: number = 0 -- The server settings' rewind.rttSmoothing, the smoothing's time constant in seconds
local BotRtt: number = 0 -- The server settings' bots.rtt in seconds, 0 on a server that creates no bots
local Started: boolean = false

local Connections = {}

-- Names a key in a refusal: a player or bot by its Name, anything else by its type
local function describe(key: any): string
	if (typeof(key) == "Instance" or type(key) == "table") and type(key.Name) == "string" then
		return key.Name
	end

	return `a {typeof(key)}`
end

-- Whether a value is a number above 0 and short of infinity, which NaN never is
local function positive(value: any): boolean
	return type(value) == "number" and value > 0 and value < math.huge
end

--[[
    Takes the server settings' rewind.rttSmoothing, the seconds every
    connection's ping samples are smoothed over, and its bots table, whose
    rtt every bot's connection reports, or nil on a server that creates no
    bots. It runs once, before the first add
--]]

function Connections.start(smoothing: number, bots: { rtt: number }?)
	if Started then
		error("Connections.start runs once, and it has already run", 2)
	elseif not positive(smoothing) then
		error(`Connections.start takes rewind.rttSmoothing in seconds above 0, and got {smoothing}`, 2)
	end

	if bots ~= nil then
		if type(bots) ~= "table" or not positive(bots.rtt) then
			error("Connections.start takes bots as a table with an rtt in seconds above 0, or nil", 2)
		end

		BotRtt = bots.rtt
	end

	Smoothing = smoothing
	Started = true
end

--[[
    The connection for a player or one of Volt's bots. A player's round trip
    is smoothed from the engine's pings it samples, and a bot's is the
    server settings' bots.rtt, so a bot needs a server whose settings give it
--]]

function Connections.add(key: Player | Bot): Connection
	if not Started then
		error("Connections.add ran before Connections.start", 2)
	end

	local engine: Player? = nil

	if typeof(key) == "Instance" then
		if not key:IsA("Player") then
			error(`Connections.add takes a Player or a bot, not the {key.ClassName} {key:GetFullName()}`, 2)
		end

		engine = key
	elseif type(key) == "table" and type(key.Name) == "string" then
		if BotRtt == 0 then
			error(`The bot {key.Name} needs a server whose settings give bots.rtt`, 2)
		end
	else
		error(`Connections.add takes a Player or a bot, not {describe(key)}`, 2)
	end

	if Records[key] then
		error(`{describe(key)} already has a connection`, 2)
	end

	local connection: Connection = setmetatable({
		player = key,
		_engine = engine,
		_sampled = false,
		_mean = 0,
		_variance = 0,
	}, Connection)

	Records[key] = connection

	return connection
end

--[[
    The connection of a player or bot, or nil for one with none
--]]

function Connections.get(key: Player | Bot): Connection?
	return Records[key]
end

--[[
    Forgets the connection of a player or bot that left
--]]

function Connections.remove(key: Player | Bot)
	if Records[key] == nil then
		error(`Connections.remove takes a player or bot with a connection, and {describe(key)} has none`, 2)
	end

	Records[key] = nil
end

--[[
    The round trip in seconds: the smoothed mean of the pings sampled, the
    engine's ping as it is now before the first sample, and a bot's the
    server settings' bots.rtt
--]]

function Connection.rtt(self: Self): number
	local engine: Player? = self._engine
	if engine == nil then
		return BotRtt
	elseif not self._sampled then
		return engine:GetNetworkPing()
	end

	-- Whiteoak TODO: Volt's batching overhead joins the round trip once G0 measures it live; until then none is added
	return self._mean
end

--[[
    The jitter in seconds, the standard deviation of the pings sampled
    under the same weights as the round trip, 0 before two samples and
    always 0 for a bot, whose round trip never changes
--]]

function Connection.jitter(self: Self): number
	return math.sqrt(self._variance)
end

--[[
    Folds the engine's ping as it is now into the smoothed round trip and
    its variance, weighting it by how much of the smoothing time has passed
    since the last sample, so a ping a whole smoothing time old counts 1/e
    of what it did. The first sample sets the round trip to the ping, and a
    bot's sample does nothing

    @ seconds | the time since this connection's last sample
--]]

function Connection.sample(self: Self, seconds: number)
	if not positive(seconds) then
		error(`connection:sample takes the seconds since its last sample, above 0 and finite, and got {seconds}`, 2)
	end

	local engine: Player? = self._engine
	if engine == nil then
		return
	end

	local ping: number = engine:GetNetworkPing()
	if not self._sampled then
		self._sampled = true
		self._mean = ping
		self._variance = 0

		return
	end

	-- The incremental form of the exponentially weighted mean and variance, which keeps no samples
	local weight: number = 1 - math.exp(-seconds / Smoothing)
	local difference: number = ping - self._mean
	local step: number = weight * difference

	self._mean += step
	self._variance = (1 - weight) * (self._variance + difference * step)
end

export type Connection = Self
type Self = typeof(setmetatable({} :: Fields, Connection))

return Connections
