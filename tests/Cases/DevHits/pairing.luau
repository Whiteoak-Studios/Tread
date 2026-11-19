--[[
    Seventy shots' reports pair with the fixture's results by their fired
    order and unwrapped counters, whatever order the results resolved in,
    and the totals and the three rates come out as planted
--]]

--!strict
local Harness = require("../../Fixtures/DevServer/Harness")

local SHOTS: number = 70 -- Counters 0 to 69, past one wrap of the 6-bit sequence
local SEQUENCES: number = 64
local FIRST_TICK: number = 1000 -- The tick counter 0 was fired on, one command each two ticks
local EVERY: number = 2
local SHUFFLE: number = 37 -- A stride coprime to the 69 results, which puts them out of fired order
local CLOSE: number = 1e-9

-- The bodies the shots strike, by slot
local A: number = 11
local B: number = 12

local LOST: number = 5 -- Its command never reached the server, though the shooter saw it strike B
local SILENT: number = 67 -- Its report never arrived, though the server ran it
local WRAPPED: number = 69 -- Its sequence on the wire is 5, the lost one's, and both sides saw it strike A

-- What each side saw of a counter, where it differs from both striking A
type Outcome = { client: number?, server: number?, reason: string?, inside: boolean? }

local OUTCOMES: { [number]: Outcome } = {
	[LOST] = { client = B },
	[10] = { client = nil, server = nil, reason = "range" }, -- Both missed
	[11] = { client = nil, server = nil, reason = "range" },
	[12] = { client = nil, server = nil, reason = "range" },
	[20] = { client = A, server = nil, reason = "range" }, -- The shooter's view alone hit
	[21] = { client = A, server = nil, reason = "range" },
	[30] = { client = nil, server = A }, -- The server alone hit
	[40] = { client = B, server = A }, -- Each hit another body
	[41] = { client = B, server = A },
	[50] = { client = nil, server = nil, reason = "cap" }, -- Both missed, past the rewind's cap
	[51] = { client = A, server = nil, reason = "cap" },
	[60] = { client = A, server = A, inside = false }, -- Claimed outside the band
	[61] = { client = A, server = A, inside = false },
}

-- The known answer
local EXPECTED: { [string]: number } = {
	paired = 68,
	lost = 1,
	unpaired = 1,
	either = 64,
	agree = 58,
	clientOnly = 3,
	serverOnly = 1,
	otherBody = 2,
	clientHits = 63,
	outside = 2,
}

local RANGE_MISSES: number = 5
local CAP_MISSES: number = 2

return function (): (boolean, string | nil)
	local loaded: Harness.Loaded = Harness.load()
	local Hits: any = loaded.require(loaded.game:GetService("ServerScriptService").Server.Hits)

	local bodies: { [number]: { _slot: number } } = { [A] = { _slot = A }, [B] = { _slot = B } }
	local reports: { any } = {}
	local fired: { any } = {}

	for counter: number = 0, SHOTS - 1 do
		local outcome: Outcome = OUTCOMES[counter] or { client = A, server = A }

		if counter ~= SILENT then
			table.insert(reports, { counter = counter, target = outcome.client })
		end

		if counter ~= LOST then
			local server: number? = outcome.server
			table.insert(fired, {
				sequence = counter % SEQUENCES,
				fired = FIRST_TICK + counter * EVERY,
				strike = server and { target = bodies[server], zone = "chest" },
				reason = outcome.reason,
				inside = outcome.inside ~= false,
			})
		end
	end

	if fired[#fired].sequence ~= LOST then
		return false, `The wrapped shot's sequence is {fired[#fired].sequence}, not the lost one's {LOST}`
	end

	-- Resolved out of fired order
	local results: { any } = {}
	for index: number = 1, #fired do
		results[index] = fired[(index * SHUFFLE) % #fired + 1]
	end

	local tally: any = Hits.pair(reports, results)
	for name: string, want: number in EXPECTED do
		if tally[name] ~= want then
			return false, `The pairing gave {tally[name]} {name}, not {want}`
		end
	end

	if tally.misses.range ~= RANGE_MISSES or tally.misses.cap ~= CAP_MISSES then
		return false, `The server's misses were {tally.misses.range} range and {tally.misses.cap} cap`
	end

	local rates: { [string]: number } = {
		eitherRate = EXPECTED.agree / EXPECTED.either,
		pairedRate = EXPECTED.agree / EXPECTED.paired,
		clientRate = EXPECTED.agree / EXPECTED.clientHits,
	}

	for name: string, want: number in rates do
		if not (math.abs(tally[name] - want) < CLOSE) then
			return false, `The {name} came out {tally[name]}, not {want}`
		end
	end

	-- Nothing to divide by gives no rate
	local empty: any = Hits.pair({}, {})
	if empty.eitherRate ~= nil or empty.pairedRate ~= nil or empty.clientRate ~= nil then
		return false, "With no shots the rates were not all missing"
	end

	return true, nil
end
