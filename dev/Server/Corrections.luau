--[[
    The correction telemetry G2 reads: every replay a client reports on the
    dev scope's corrected event, counted small or large for each player
    from their first character until they leave
--]]

--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Packages = ReplicatedStorage.Packages

local Volt = require(Packages.Volt)

local Network = require(ReplicatedStorage.Shared.Network.Server)

local RATE: { perSecond: number, burst: number } = require(ServerScriptService.Server.Config.Corrections).rate
local SMALL: number = require(ServerScriptService.Server.Config.Corrections).small
local SECONDS_PER_MINUTE: number = 60
local F32_BYTES: number = 4

-- A size arrives as the f32 nearest it, so the limit is compared as the f32 nearest it too, and a replay of exactly
-- the limit counts small
local Wire: buffer = buffer.create(F32_BYTES)
buffer.writef32(Wire, 0, SMALL)

local SMALL_ON_WIRE: number = buffer.readf32(Wire, 0)

type Key = Player | Volt.Bot

-- A player's corrections since counting began, as a read hands them out
export type Counts = {
	small: number,
	large: number,
	minutes: number, -- Since counting began, which each count is divided by for its rate a minute
}

type Record = {
	small: number,
	large: number,
	since: number, -- The clock when counting began
}

local Records: { [Key]: Record } = {} -- Each counted player's, cleared when they leave
local Started: boolean = false

local Corrections = {}

-- Counts one replay a client reported, for a player being counted; a size below 0 is no replay's and is dropped
local function count(key: Key, size: number, flagged: boolean)
	local record: Record? = Records[key]
	if not record or not (size >= 0) then
		return
	end

	if flagged or size > SMALL_ON_WIRE then
		record.large += 1
	else
		record.small += 1
	end
end

--[[
    Binds the corrected event at the dev game's own rate and starts
    counting what arrives on it. It runs once a server, and its listener
    lives as long as the server
--]]

function Corrections.start()
	if Started then
		error("Corrections.start runs once a server, and it has already run", 2)
	end

	Started = true
	Network.rate("corrected", RATE.perSecond, RATE.burst)
	Network.corrected.on(count)
end

--[[
    Starts counting a player's corrections from now, at their first
    character. A player already counted keeps the counts they have
--]]

function Corrections.add(key: Key)
	if Records[key] then
		return
	end

	Records[key] = { small = 0, large = 0, since = os.clock() }
end

--[[
    A player's small and large corrections since counting began and the
    minutes that covers, in a table of the read's own, or nil for a player
    not being counted
--]]

function Corrections.get(key: Key): Counts?
	local record: Record? = Records[key]
	if not record then
		return nil
	end

	local minutes: number = (os.clock() - record.since) / SECONDS_PER_MINUTE

	return { small = record.small, large = record.large, minutes = minutes }
end

--[[
    Stops counting a player who left, and forgets their counts
--]]

function Corrections.remove(key: Key)
	Records[key] = nil
end

return Corrections
