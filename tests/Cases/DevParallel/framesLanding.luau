--[[
    ParallelFrames' rounds are counted at the first event every worker's
    result was readable at, a round never all in as later or never, and a
    PostSimulation send shows no column of its own frame's PostSimulation
--]]

--!strict
local Harness = require("../../Fixtures/DevServer/Harness")

local WORKERS: number = 4
local PRE: string = "PreSimulation"
local POST: string = "PostSimulation"
local HEART: string = "Heartbeat"

-- A log of frame events: a Heartbeat, four frames as expected, one with a second PostSimulation, one of a Heartbeat
-- alone, then a PreSimulation whose frame never ends
local KINDS: { string } = {
	HEART, -- 1
	PRE, -- 2
	POST,
	HEART, -- 4
	PRE, -- 5
	POST,
	HEART, -- 7
	PRE, -- 8
	POST,
	HEART, -- 10
	PRE, -- 11
	POST,
	HEART, -- 13
	PRE, -- 14
	POST,
	POST,
	HEART, -- 17
	HEART, -- 18
	PRE, -- 19
}

local ODD: number = 2 -- The frame with two PostSimulations and the one of a Heartbeat alone

-- A round handed out at that event of the log, with how many results were readable at each event after it
local function roundAt(at: number, seen: { number }): { [string]: any }
	return { sent = 0, at = at, seen = seen, starts = {}, finishes = {} }
end

-- PreSimulation sends, each with the column worked out by walking the log from the event after its send
local PRE_ROUNDS: { { round: { [string]: any }, column: string } } = {
	{ round = roundAt(2, { 4 }), column = "the same PostSimulation" }, -- All in at 3
	{ round = roundAt(5, { 3, 4 }), column = "the same Heartbeat" }, -- 3 of 4 at 6, all at 7
	{ round = roundAt(8, { 2, 4 }), column = "the same Heartbeat" }, -- At 10
	{ round = roundAt(11, { 0, 4 }), column = "the same Heartbeat" }, -- At 13
	{ round = roundAt(8, { 0, 2, 4 }), column = "the next PreSimulation" }, -- The last result one event later, at 11
	{ round = roundAt(2, { 0, 0, 0, 4 }), column = "the next PostSimulation" }, -- At 6, past the Heartbeat at 4
	{ round = roundAt(2, { 0, 0, 0, 0, 4 }), column = "the next Heartbeat" }, -- At 7
	{ round = roundAt(2, { 0, 0, 0, 0, 0, 4 }), column = "later or never" }, -- At 8, two Heartbeats on
	{ round = roundAt(2, { 1, 2, 3, 3 }), column = "later or never" }, -- Never all in, its last read at 6
}

local PRE_COUNTS: string =
	"the same PostSimulation 1, the same Heartbeat 3, the next PreSimulation 1, the next PostSimulation 1, the next Heartbeat 1, later or never 2"

-- PostSimulation sends the same way, one of them in the frame with a second PostSimulation
local POST_ROUNDS: { { round: { [string]: any }, column: string } } = {
	{ round = roundAt(3, { 4 }), column = "the same Heartbeat" }, -- At 4
	{ round = roundAt(6, { 4 }), column = "the same Heartbeat" }, -- At 7
	{ round = roundAt(3, { 2, 4 }), column = "the next PreSimulation" }, -- At 5
	{ round = roundAt(3, { 0, 0, 4 }), column = "the next PostSimulation" }, -- At 6
	{ round = roundAt(3, { 0, 0, 0, 4 }), column = "the next Heartbeat" }, -- At 7
	{ round = roundAt(3, { 0, 0, 0, 0 }), column = "later or never" }, -- Never all in, its last read the Heartbeat at 7
	{ round = roundAt(15, { 4 }), column = "later or never" }, -- At 16, its own frame's second PostSimulation
}

local POST_COUNTS: string =
	"the same Heartbeat 2, the next PreSimulation 1, the next PostSimulation 1, the next Heartbeat 1, later or never 2"

-- The tally as one text, each column's label then its count
local function written(tallied: { any }): string
	local parts: { string } = {}
	for _, count: any in tallied do
		table.insert(parts, `{count.label} {count.count}`)
	end

	return table.concat(parts, ", ")
end

return function (): (boolean, string | nil)
	local loaded: Harness.Loaded = Harness.load()
	local Frames: any = loaded.require(loaded.game:GetService("ServerScriptService").Server.Parallel.Frames)

	local sends: { { send: string, rounds: { any }, counts: string } } = {
		{ send = PRE, rounds = PRE_ROUNDS, counts = PRE_COUNTS },
		{ send = POST, rounds = POST_ROUNDS, counts = POST_COUNTS },
	}

	for _, case in sends do
		-- 1) Each round at its own column
		local columns: { any } = Frames.columns(case.send)
		local rounds: { any } = {}

		for index: number, expected: any in case.rounds do
			local column: string = Frames.landing(KINDS, expected.round, WORKERS, columns)
			if column ~= expected.column then
				return false, `{case.send} round {index} was counted at {column}, not {expected.column}`
			end

			table.insert(rounds, expected.round)
		end

		-- 2) The tally, in the line's order, with a PostSimulation send's own PostSimulation left out
		local tallied: string = written(Frames.tally(KINDS, rounds, WORKERS, case.send))
		if tallied ~= case.counts then
			return false, `{case.send} sends were tallied as "{tallied}", not "{case.counts}"`
		end
	end

	-- 3) The frames out of the expected order, the first Heartbeat's partial frame before it and the unended one after
	-- left out
	local odd: number = Frames.odd(KINDS)
	if odd ~= ODD then
		return false, `The log counted {odd} odd frames, not {ODD}`
	end

	return true, nil
end
