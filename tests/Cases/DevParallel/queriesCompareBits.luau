--[[
    The probe's comparison of two runs' results by bits: equal streams with a
    NaN differ nowhere, one changed value is one difference in its kind and
    query, a 0 against a -0 differs only in sign, and a short run is missing
--]]

--!strict
local Harness = require("../../Fixtures/DevServer/Harness")

local PLAN_WIDTH: number = 8
local RESULT_WIDTH: number = 9
local F64_BYTES: number = 8
local RECORD_BYTES: number = RESULT_WIDTH * F64_BYTES
local PARTIAL_BYTES: number = 10 -- A cut record's bytes past the last whole one
local NAN: number = 0 / 0
local DISTANCE: number = 7 -- Each value's place in a result, from 0
local NORMAL_X: number = 4
local POSITION_X: number = 1

-- Each query's kind, in a plan whose other values compare never reads
local KINDS: { number } = { 1, 1, 2, 2, 3, 4 }

-- Our results: a ray hit and miss, two sweep hits, a sphere hit with a NaN, and a rest's height
local OURS: { { number } } = {
	{ 1, 1, 2, 3, 0, 1, 0, 2, 800 },
	{ 0, 0, 0, 0, 0, 0, 0, 0, 0 },
	{ 2, 4, 5, 6, 0, 0, 1, 2, 512 },
	{ -1, 4, 5, 6, 0, 1, 0, 0, 512 },
	{ 1, NAN, 2, 3, 0, 1, 0, 1, 1280 },
	{ 1, 0, 0, 0, 0, 0, 0, 3, 0 },
}

-- Each kind's queries and hits on our side: the ray's miss is the one query without a hit
local QUERIES: { number } = { 2, 2, 1, 1 }
local HITS: { number } = { 1, 2, 1, 1 }

local function stream(records: { { number } }): buffer
	local made: buffer = buffer.create(#records * RECORD_BYTES)
	for record: number, values: { number } in records do
		for field: number, value: number in values do
			buffer.writef64(made, (record - 1) * RECORD_BYTES + (field - 1) * F64_BYTES, value)
		end
	end

	return made
end

-- The same bytes with one value of one query, both from 1, rewritten
local function changed(base: buffer, query: number, field: number, value: number): buffer
	local copy: buffer = buffer.create(buffer.len(base))
	buffer.copy(copy, 0, base)
	buffer.writef64(copy, (query - 1) * RECORD_BYTES + field * F64_BYTES, value)

	return copy
end

--[[
    Whether the tallies hold what was expected of each kind: no difference
    in every kind but the one named, which holds the counts and first
    difference given
--]]

local function expect(
	tallies: any,
	odd: number?,
	differing: number,
	signOnly: number,
	missing: number,
	first: string?
): string?
	local names: { string } = { "ray", "sweep", "sphere", "rest" }
	if #tallies ~= #names then
		return `{#tallies} tallies came back, not {#names}`
	end

	for kind: number, tally: any in tallies do
		local wanted: { any } = { 0, 0, 0, nil }
		if kind == odd then
			wanted = { differing, signOnly, missing, first }
		end

		if tally.kind ~= names[kind] or tally.queries ~= QUERIES[kind] or tally.hits ~= HITS[kind] then
			return `Tally {kind} was {tally.kind} of {tally.queries} queries and {tally.hits} hits`
		elseif tally.differing ~= wanted[1] or tally.signOnly ~= wanted[2] or tally.missing ~= wanted[3] then
			return `{tally.kind}: {tally.differing} differing, {tally.signOnly} sign only, {tally.missing} missing`
		elseif tally.first ~= wanted[4] then
			return `{tally.kind}'s first difference was "{tally.first}", not "{wanted[4]}"`
		end
	end

	return nil
end

return function (): (boolean, string | nil)
	local loaded: any = Harness.load()
	local Queries: any = loaded.require(loaded.game:GetService("ServerScriptService").Server.Parallel.Queries)

	local plan: buffer = buffer.create(#KINDS * PLAN_WIDTH * F64_BYTES)
	for query: number, kind: number in KINDS do
		buffer.writef64(plan, (query - 1) * PLAN_WIDTH * F64_BYTES, kind)
	end

	local ours: buffer = stream(OURS)

	-- 1) The same bytes differ nowhere, the NaN included
	local problem: string? = expect(Queries.compare(plan, ours, stream(OURS)), nil, 0, 0, 0, nil)
	if problem then
		return false, `Equal streams: {problem}`
	end

	-- 2) The first sweep's distance, 2 against 3, is one difference in the sweep's first query
	local theirs: buffer = changed(ours, 3, DISTANCE, 3)
	local first: string = "query 1 distance: ours 4000000000000000, theirs 4008000000000000"
	problem = expect(Queries.compare(plan, ours, theirs), 2, 1, 0, 0, first)
	if problem then
		return false, `One changed distance: {problem}`
	end

	-- 3) The second sweep's normal against a -0 differs only in the sign of a zero
	theirs = changed(ours, 4, NORMAL_X, -0)
	first = "query 2 normal.x: ours 0000000000000000, theirs 8000000000000000"
	problem = expect(Queries.compare(plan, ours, theirs), 2, 1, 1, 0, first)
	if problem then
		return false, `A -0 normal: {problem}`
	end

	-- 4) A sphere position of 1 against our NaN is a difference in value
	theirs = changed(ours, 5, POSITION_X, 1)
	local tallies: any = Queries.compare(plan, ours, theirs)
	if tallies[3].differing ~= 1 or tallies[3].signOnly ~= 0 then
		return false, `A NaN against 1 gave {tallies[3].differing} differing, {tallies[3].signOnly} of them sign only`
	end

	-- 5) Their run cut inside the rest's record is the rest missing, and the cut bytes are never read
	theirs = buffer.create((#OURS - 1) * RECORD_BYTES + PARTIAL_BYTES)
	buffer.copy(theirs, 0, ours, 0, buffer.len(theirs))
	first = "query 1: ours holds 6 results and theirs 5, of 6 queries"
	problem = expect(Queries.compare(plan, ours, theirs), 4, 1, 0, 1, first)
	if problem then
		return false, `A short run: {problem}`
	end

	return true, nil
end
