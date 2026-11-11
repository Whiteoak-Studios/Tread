--[[
    The server's check refuses server settings with a key missing, of the
    wrong kind, out of its range or unknown, a rate for no endpoint among
    them, naming the key by its full path
--]]

--!strict
local Environment = require("../../Environment")

local CONFIG: string = "src/Config.luau"
local CONSTANTS: string = "src/Constants.luau"
local EXAMPLE: string = "tests/Fixtures/Config/Example.luau"
local BOTS: string = "bots." -- Starts the path of a key inside the bots table
local BOT_RTT: number = 0.1 -- Seconds, a bot harness's configured round trip

type Refusal = { path: string, value: any }

return function (): (boolean, string | nil)
	local Config = Environment.load(CONFIG)
	local Example = Environment.load(EXAMPLE)
	local slots: number = Environment.load(CONSTANTS).SLOTS

	local refusals: { Refusal } = {
		{ path = "rates", value = nil },
		{ path = "rates.move", value = nil },
		{ path = "rates.move.perSecond", value = 0 },
		{ path = "rates.move.burst", value = 0.5 },
		{ path = "rates.move.burst", value = nil },
		{ path = "rates.jump", value = { perSecond = 10, burst = 10 } },
		{ path = "catchUp", value = 0 },
		{ path = "catchUp", value = 1.5 },
		{ path = "slots.reserve", value = slots + 1 },
		{ path = "slots.reserve", value = -1 },
		{ path = "slots.reserve", value = 1.5 },
		{ path = "relevancy.leave", value = nil },
		{ path = "tiers.farAim", value = "15" },
		{ path = "weights.cone", value = 0 },
		{ path = "shotNear.seconds", value = -5 },
		{ path = "budget.hard", value = nil },
		{ path = "antiEsp.aim", value = nil },
		{ path = "antiEsp.slice", value = 0 },
		{ path = "footsteps.range.crouch", value = 20 },
		{ path = "footsteps.range.walk", value = 0 },
		{ path = "footsteps.stride.walk", value = nil },
		{ path = "footsteps.stride", value = nil },
		{ path = "sleepers.rays", value = 2.5 },
		{ path = "npcs.farRate", value = 0 },
		{ path = "history.seconds", value = 0 },
		{ path = "rewind.extra", value = -1 },
		{ path = "rewind.bandMax", value = nil },
		{ path = "teleport", value = nil },
		{ path = "teleport.timeout", value = 0 },
		{ path = "beforeCommand", value = nil },
		{ path = "beforeCommand", value = 5 },
		{ path = "prestream", value = 5 },
		{ path = "bots", value = 5 },
		{ path = "bots.rtt", value = nil },
		{ path = "bots.rtt", value = 0 },
		{ path = "bots.rtt", value = -0.1 },
		{ path = "bots.count", value = 1 },
		{ path = "rate", value = {} },
	}

	for _, refusal: Refusal in refusals do
		local server = Example.server()

		-- A bots table to break, since the World's servers give none
		if string.find(refusal.path, BOTS, 1, true) == 1 then
			server.bots = { rtt = BOT_RTT }
		end

		Example.set(server, refusal.path, refusal.value)

		local problem: string? = Example.refusal(Config.server, `server.{refusal.path}`, Example.shared(), server)
		if problem then
			return false, problem
		end
	end

	local missing: string? = Example.refusal(Config.server, "server", Example.shared(), nil)
	if missing then
		return false, missing
	end

	return true, nil
end
