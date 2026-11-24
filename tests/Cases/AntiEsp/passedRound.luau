--[[
    AntiEsp.passed opens the relay's round as an ask does when it is a
    run's first call, so the pairs it keeps carry that run's round and a
    viewer neither asked nor passed in it is dropped, while a count of 0
    opens none; and its refusals
--]]

--!strict
local Environment = require("../../Environment")
local Refuses = require("../../Fixtures/Codec/Refuses")

local HARNESS: string = "tests/Fixtures/AntiEsp/Harness.luau"
local CONSTANTS: string = "src/Constants.luau"
local INTERVAL: number = 0.5 -- Seconds between a visible pair's rechecks, at the example's 2 Hz

-- Each run after the first: whether the other viewer asks, after passed, and passed's count; and whether each
-- viewer's pair is rechecked at that run's slice, one interval on
local RUNS: { { asks: boolean, count: number, left: boolean, other: boolean } } = {
	{ asks = true, count = 1, left = true, other = true }, -- passed first, then the other's ask, in one round
	{ asks = false, count = 1, left = true, other = false }, -- passed alone opens a round the other isn't in
	{ asks = false, count = 0, left = true, other = false }, -- A count of 0 opens none, so the kept pair stays
}

return function (): (boolean, string | nil)
	-- 1) The refusals: before start, and a value that is no slot
	local Constants: any = Environment.load(CONSTANTS)
	local Unstarted: any = Environment.load(HARNESS)
	local nobody: any = { key = { Name = "Nobody" }, position = vector.zero, acknowledged = 0, received = 0 }

	local refused: boolean, why: string = Refuses("before AntiEsp.start", Unstarted.AntiEsp.passed, nobody, { 0 }, 1)
	if not refused then
		return false, `passed before start went another way: {why}`
	end

	-- Started, with the viewer never asked about, so it holds no pair, and each slot is still checked
	local Probe: any = Environment.load(HARNESS)
	Probe.new(nil, Probe.clock().read)

	for _, value: number in { -1, Constants.SLOTS, 1.5 } do
		refused, why = Refuses("the slot table's slots", Probe.AntiEsp.passed, nobody, { value }, 1)
		if not refused then
			return false, `passed of {value} went another way: {why}`
		end
	end

	-- 2) Two viewers, each seen the one target at 0 s
	local Harness: any = Environment.load(HARNESS)
	local harness: any = Harness.new(nil, Harness.clock().read)
	local AntiEsp: any = Harness.AntiEsp

	local _, left: any = harness:player("Left", vector.zero)
	local _, other: any = harness:player("Other", vector.create(0, 0, 50))
	local target: number = harness:body("Player", vector.create(20, 0, 0))
	local head: number = harness.server.antiEsp.aim.Stand[1].up

	-- Whether a slice's rays held one from a viewer's eye, at the target's head with every ray open
	local function rechecked(viewer: any): boolean
		for _, ray: any in harness.rays do
			if ray.origin.z == viewer.position.z and ray.to.y == head then
				return true
			end
		end

		return false
	end

	AntiEsp.isHidden(left, target)
	AntiEsp.isHidden(other, target)
	harness:slice(0)

	for index: number, run in RUNS do
		AntiEsp.passed(left, { target }, run.count)
		if run.asks then
			AntiEsp.isHidden(other, target)
		end

		harness:slice(index * INTERVAL)

		if rechecked(left) ~= run.left then
			return false, `Run {index + 1}'s slice rechecked the left viewer's pair {rechecked(left)}`
		elseif rechecked(other) ~= run.other then
			return false, `Run {index + 1}'s slice rechecked the other viewer's pair {rechecked(other)}`
		end
	end

	-- The left viewer's pair kept through every run, and the other's dropped in the run it had no part in
	if AntiEsp.isHidden(left, target) then
		return false, "The left viewer's kept pair restarted hidden"
	elseif not AntiEsp.isHidden(other, target) or AntiEsp.reason(other.key, target) ~= "Untested" then
		return false, `The other viewer's dropped pair's next ask found {AntiEsp.reason(other.key, target)}`
	end

	return true, nil
end
