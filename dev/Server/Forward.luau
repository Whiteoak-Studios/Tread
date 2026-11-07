--[[
    The report forward: each report Tread's server raises about a player
    the exploit kit is for, sent to them over the dev scope for its panel,
    at most at the dev server's rate, counting each one it drops
--]]

--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Packages = ReplicatedStorage.Packages

local Tread = require(Packages.Tread)

local Network = require(ReplicatedStorage.Shared.Network.Server)

local Exploiters = require(ReplicatedStorage.Shared.Dev.Exploiters)

local RATE: { perSecond: number, burst: number } = require(ServerScriptService.Server.Config.Forward).rate
local KIND_BYTES: number = 16 -- The dev schema's bound on a report's kind
local DETAIL_BYTES: number = 64 -- And on its detail
local NUMBER_FORMAT: string = "%.6g" -- A measurement that is a number, to six significant digits

type Key = Player | Tread.Bot

-- A player's share of the rate: the reports it has room for, when that was counted, and the ones past it
type Bucket = {
	tokens: number,
	counted: number,
	dropped: number,
}

local Buckets: { [Key]: Bucket } = {} -- Each player the kit is for whom the dev scope has joined, until they leave
local Started: boolean = false

local Forward = {}

-- One report on its way to the player it is about, when the kit is for them and their share of the rate has room
local function forward(player: Key?, kind: string, measurement: number | string)
	if player == nil then
		return
	end

	local bucket: Bucket? = Buckets[player]
	if not bucket then
		return
	end

	local now: number = os.clock()
	bucket.tokens = math.min(bucket.tokens + (now - bucket.counted) * RATE.perSecond, RATE.burst)
	bucket.counted = now

	if bucket.tokens < 1 then
		bucket.dropped += 1
		return
	end

	bucket.tokens -= 1

	local detail: string
	if type(measurement) == "number" then
		detail = string.format(NUMBER_FORMAT, measurement)
	else
		detail = measurement
	end

	Network.report.fire(player, string.sub(kind, 1, KIND_BYTES), string.sub(detail, 1, DETAIL_BYTES), bucket.dropped)
end

--[[
    Starts forwarding, once a server, the reports of each player the dev
    scope joins, never a bot, whom the exploit kit is for, as the kit gates
    itself: in Studio, or by the exploiter list. From their join until they
    leave, on the dev scope's own runtime; its callbacks live as long as
    the server
--]]

function Forward.start(server: Tread.Server)
	if Started then
		error("Forward.start runs once a server, and it has already run", 2)
	end

	Started = true

	Network.onJoin(function (player: Key)
		-- A bot has no UserId, so it is told apart first
		if not Network.isBot(player) and Exploiters.allows((player :: Player).UserId) then
			Buckets[player] = { tokens = RATE.burst, counted = os.clock(), dropped = 0 }
		end
	end)

	Network.onLeave(function (player: Key)
		Buckets[player] = nil
	end)

	server:onReport(forward)
end

return Forward
