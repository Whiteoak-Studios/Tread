--[[
    AntiEsp.passed runs inside a relay round's hold as an ask does, keeping
    a left viewer's pairs, and a leave held beside it still forgets the
    viewer at the release; called first after a slice, it keeps the pairs
    the run before it asked about, as the next run's
--]]

--!strict
local Environment = require("../../Environment")

local HARNESS: string = "tests/Fixtures/AntiEsp/Harness.luau"
local REACH: number = 4 -- Studs across the ground from a body's feet that every ray to it ends within
local INTERVAL: number = 0.5 -- Seconds between a visible pair's rechecks, at the example's 2 Hz

return function (): (boolean, string | nil)
	local Harness: any = Environment.load(HARNESS)
	local harness: any = Harness.new(nil, Harness.clock().read)
	local AntiEsp: any = Harness.AntiEsp
	AntiEsp.useWhole(true)

	local _, left: any = harness:player("Left", vector.zero)
	local _, leaving: any = harness:player("Leaving", vector.create(-50, 0, 0))
	local _, other: any = harness:player("Other", vector.create(0, 0, 50))
	local target: number = harness:body("Player", vector.create(20, 0, 0))

	-- Whether a slice's rays held one from a viewer's eye, straight above where it stands, to the target
	local function rechecked(viewer: any): boolean
		local feet: vector = harness.states[target].position

		for _, ray: any in harness.rays do
			local offset: vector = ray.to - feet
			local from: boolean = ray.origin.x == viewer.position.x and ray.origin.z == viewer.position.z
			if from and math.sqrt(offset.x * offset.x + offset.z * offset.z) < REACH then
				return true
			end
		end

		return false
	end

	-- Every viewer's pair seen at 0 s
	for _, viewer: any in { left, leaving, other } do
		AntiEsp.isHidden(viewer, target)
	end

	harness:slice(0)

	-- 1) A round held out: the other viewer asks, the two left ones are passed, and one of them leaves inside it
	AntiEsp.hold()
	AntiEsp.isHidden(other, target)

	local ran: boolean, why: any = pcall(AntiEsp.passed, left, { target }, 1)
	if not ran then
		return false, `passed refused inside a hold: {why}`
	end

	AntiEsp.leave(leaving.key)
	AntiEsp.passed(leaving, { target }, 1)
	AntiEsp.release()

	harness:slice(INTERVAL)

	if not rechecked(left) or not rechecked(other) then
		return false, "A pair kept or asked inside the hold wasn't rechecked after its release"
	elseif rechecked(leaving) then
		return false, "The viewer that left inside the hold kept its pair past the release"
	elseif AntiEsp.reason(leaving.key, target) ~= "Untested" then
		return false, `The viewer that left read {AntiEsp.reason(leaving.key, target)} after the release`
	end

	-- 2) The next run's first call is passed, after the slice: it opens that run's round and keeps the pair
	AntiEsp.passed(left, { target }, 1)
	AntiEsp.isHidden(other, target)
	harness:slice(2 * INTERVAL)

	if not rechecked(left) then
		return false, "The pair passed kept as a run's first call after a slice wasn't rechecked"
	elseif AntiEsp.isHidden(left, target) or AntiEsp.reason(left.key, target) ~= "Clear" then
		return false, `The kept pair's next ask found {AntiEsp.reason(left.key, target)}`
	end

	return true, nil
end
