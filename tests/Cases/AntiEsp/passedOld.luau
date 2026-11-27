--[[
    AntiEsp.passed keeps only what the round before asked about: a pair the
    relay already left out of a run stays dropped, is never tested again,
    and its next ask starts it afresh, hidden; a pair the round before
    asked about whose slot has a new life since starts afresh as an ask
    would start it, hidden and tested at once
--]]

--!strict
local Environment = require("../../Environment")

local HARNESS: string = "tests/Fixtures/AntiEsp/Harness.luau"
local REACH: number = 4 -- Studs across the ground from a body's feet that every ray to it ends within
local DUE: number = 0.5 -- When every pair seen at 0 s is rechecked, at the example's 2 Hz

return function (): (boolean, string | nil)
	local Harness: any = Environment.load(HARNESS)
	local clock: any = Harness.clock()
	local harness: any = Harness.new(nil, clock.read)
	local AntiEsp: any = Harness.AntiEsp

	local _, left: any = harness:player("Left", vector.zero)
	local _, other: any = harness:player("Other", vector.create(0, 0, 50))
	local dropped: number = harness:body("Player", vector.create(20, 0, 0))
	local reborn: number = harness:body("Player", vector.create(-20, 0, 0))

	-- How many of a slice's rays the left viewer cast at a body
	local function raysAt(slot: number): number
		local feet: vector = harness.states[slot].position
		local count: number = 0

		for _, ray: any in harness.rays do
			local offset: vector = ray.to - feet
			if ray.origin.z == left.position.z and math.sqrt(offset.x * offset.x + offset.z * offset.z) < REACH then
				count += 1
			end
		end

		return count
	end

	-- Both seen at 0 s
	AntiEsp.isHidden(left, dropped)
	AntiEsp.isHidden(left, reborn)
	AntiEsp.isHidden(other, dropped)
	harness:slice(0)

	-- The next run leaves the dropped pair out, as one past the left viewer's relevance, and hands passed the pair of
	-- a slot that has a new life since, which starts afresh, hidden and due at once, as its ask would have started it
	harness:reborn(reborn)
	AntiEsp.isHidden(other, dropped)
	AntiEsp.passed(left, { reborn }, 1)

	if AntiEsp.reason(left.key, reborn) ~= "Untested" then
		return false, `passed left a new life's pair at {AntiEsp.reason(left.key, reborn)}, not started afresh`
	end

	harness:slice(0.1)

	if raysAt(reborn) ~= 1 then
		return false, `The new life's pair passed kept cast {raysAt(reborn)} rays at once, not its first test's 1`
	end

	-- The run after leaves the viewer out, handing passed both
	AntiEsp.isHidden(other, dropped)
	AntiEsp.passed(left, { dropped, reborn }, 2)
	harness:slice(DUE)

	if raysAt(dropped) ~= 0 then
		return false, `passed kept a pair the relay had already left out, which cast {raysAt(dropped)} rays`
	elseif harness:endingAt(vector.create(20, harness.server.antiEsp.aim.Stand[1].up, 0)) ~= 1 then
		return false, "The other viewer's pair, asked each run, wasn't rechecked"
	end

	-- The dropped pair's next ask starts it afresh, and the new life's keeps its own test
	if not AntiEsp.isHidden(left, dropped) or AntiEsp.reason(left.key, dropped) ~= "Untested" then
		return false, `The dropped pair's next ask found {AntiEsp.reason(left.key, dropped)}, not a new pair`
	elseif AntiEsp.isHidden(left, reborn) or AntiEsp.reason(left.key, reborn) ~= "Clear" then
		return false, `The new life's pair's next ask found {AntiEsp.reason(left.key, reborn)}, not its own test`
	end

	return true, nil
end
