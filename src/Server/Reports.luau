--[[
    The one server signal per event behind server:onReport, which every
    unit of the server fires with the player, the kind and the measurement
--]]

--!strict
-- Every kind Tread reports: its own, then Volt's failures on Tread's scope under Volt's own names
local KINDS: { [string]: boolean } = {
	moveTamper = true,
	schema = true,
	rate = true,
	gap = true,
	late = true,
	standIn = true,
	lateShot = true,
	ahead = true,
	band = true,
	snapBack = true,
	stuck = true,
	sleep = true,
	stage = true,
	packet = true,
	handshake = true,
	listener = true,
	handler = true,
	outgoing = true,
	queue = true,
	departed = true,
}

export type Kind =
	"moveTamper"
	| "schema"
	| "rate"
	| "gap"
	| "late"
	| "standIn"
	| "lateShot"
	| "ahead"
	| "band"
	| "snapBack"
	| "stuck"
	| "sleep"
	| "stage"
	| "packet"
	| "handshake"
	| "listener"
	| "handler"
	| "outgoing"
	| "queue"
	| "departed"

type Bot = { Name: string }
type Callback = (player: (Player | Bot)?, kind: Kind, measurement: number | string) -> ()
type Listener = { callback: Callback, connected: boolean }

-- The game's callbacks, in the order they connected
local Listeners: { Listener } = {}

local Reports = {}

--[[
    Calls back on every report, with the player or bot it is about, nil
    for an NPC or the server itself, its kind and its measurement. Returns
    the closure that disconnects the callback
--]]

function Reports.connect(callback: Callback): () -> ()
	if type(callback) ~= "function" then
		error(`Reports.connect takes a function, not a {typeof(callback)}`, 2)
	end

	local listener: Listener = { callback = callback, connected = true }
	table.insert(Listeners, listener)

	return function ()
		listener.connected = false

		local index: number? = table.find(Listeners, listener)
		if index then
			table.remove(Listeners, index)
		end
	end
end

-- Runs where a callback's error was raised, so its warning keeps the callback's stack
local function warnFailure(message: any)
	warn(`A report callback threw, and the other callbacks still ran: {debug.traceback(tostring(message), 2)}`)
end

-- Whether a report's subject is a player or one of Volt's bots
local function reportable(player: Player | Bot): boolean
	if typeof(player) == "Instance" then
		return player:IsA("Player")
	end

	return type(player) == "table" and type(player.Name) == "string"
end

--[[
    Reports one event to every callback. Each runs under its own xpcall, so
    one that throws is warned with its stack and never stops the others or
    the stage that reported
--]]

function Reports.fire(player: (Player | Bot)?, kind: Kind, measurement: number | string)
	if not KINDS[kind] then
		error(`Reports.fire takes a kind Tread reports, not {kind}`, 2)
	elseif type(measurement) ~= "number" and type(measurement) ~= "string" then
		error(`Reports.fire takes a number or a string as the measurement, not a {typeof(measurement)}`, 2)
	elseif player ~= nil and not reportable(player) then
		error(`Reports.fire takes a Player, a bot or nil as the player, not a {typeof(player)}`, 2)
	end

	-- A copy, so a callback connected mid-fire waits for the next report and one disconnected mid-fire is skipped
	for _, listener: Listener in table.clone(Listeners) do
		if listener.connected then
			xpcall(listener.callback, warnFailure, player, kind, measurement)
		end
	end
end

return Reports
