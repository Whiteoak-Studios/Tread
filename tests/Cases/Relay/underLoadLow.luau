--[[
    While the far rate under load lowers the farthest band, a player there a
    lower rate already holds keeps it and goes no lower: one held to an
    out-of-view rate, or the crowd cap's rest at a crowd rate, under half of
    the band's
--]]

--!strict
local Environment = require("../../Environment")

local HARNESS: string = "tests/Fixtures/Relay/Harness.luau"
local BUDGET: number = 1 -- Stand-in seconds, which every run's one read of STEP passes, one viewer leaving none
local STEP: number = 2
local UNDER_LOAD: { runs: number, scale: number } = { runs = 1, scale = 0.5 } -- Lowered from the second run on
local CROWD: { size: number, rate: number, floor: number } = { size = 1, rate = 5, floor = 5 }
local SETTLE: number = 4 -- Runs before the count, past the reveals and the lowering
local COUNTED: number = 40 -- Runs counted, 2 s at the example's 20 Hz relay
local STRIDE: number = 0.1 -- Studs every body moves a run, back and forth, so each always has a change to send
local LOOK: vector = vector.create(0, 0, -1)

-- The seated viewer stands at the origin looking along -Z: one player in view and one behind, both in the farthest band;
-- and with the crowd cap, its one member in the first band and the rest in view in the farthest
local CONE: { [string]: vector } = { ahead = vector.create(0, 0, -800), behind = vector.create(0, 0, 800) }
local CAPPED: { [string]: vector } = { member = vector.create(0, 0, -50), ahead = vector.create(0, 0, -800) }

-- Records over the counted runs, by hand, from the example's farthest band of 15 Hz with a 10 Hz floor, lowered to 7.5
-- and 5: in view, 7.5 Hz for 2 s against 15; behind, the example's 5 Hz out-of-view rate either way, the lower of it and
-- the band's; the crowd's rest the crowd rate's 5 Hz either way; its member the first band's 20 Hz
local CONE_LOWERED: { [string]: number } = { ahead = 15, behind = 10 }
local CONE_PLAIN: { [string]: number } = { ahead = 30, behind = 10 }
local CAPPED_LOWERED: { [string]: number } = { member = 40, ahead = 10 }
local CAPPED_PLAIN: { [string]: number } = { member = 40, ahead = 10 }

-- The example's tables with the crowd cap and no out-of-view rate, so the rest is held by the crowd rate alone
local function capped(_: any, server: any)
	server.tiers.outOfView = nil
	server.tiers.crowd = table.clone(CROWD)
end

-- Each body's records over the counted runs, with or without the far rate under load, and the runs it lowered
local function drive(
	tweak: ((shared: any, server: any) -> ())?,
	places: { [string]: vector },
	underLoad: { runs: number, scale: number }?
): ({ [string]: number }, number)
	local Harness: any = Environment.load(HARNESS)
	local harness: any = Harness.new(nil, tweak)

	local seated: any = harness:viewer("Seated")
	seated.viewer.slot = harness:spawn("Player", vector.zero)
	seated.viewer.look = LOOK

	local slots: { [string]: number } = {}
	for name: string, at: vector in places do
		slots[name] = harness:spawn("Player", at)
	end

	harness.step = STEP
	Harness.Relay.setBudget(BUDGET)
	if underLoad then
		Harness.Relay.setUnderLoad(underLoad)
	end

	local counts: { [string]: number } = {}
	for run: number = 1, SETTLE + COUNTED do
		local step: number = run % 2 == 0 and -STRIDE or STRIDE
		for _, slot: number in slots do
			harness.states[slot].position += vector.create(step, 0, 0)
		end

		harness:run()

		if run > SETTLE then
			for name: string, slot: number in slots do
				counts[name] = (counts[name] or 0) + Harness.count(seated.seen.records, slot)
			end
		end
	end

	local _, _, halved: number = Harness.Relay.caps()

	return counts, halved
end

-- Why a drive's records came otherwise than worked out, or nil
local function compare(
	name: string,
	tweak: ((shared: any, server: any) -> ())?,
	places: { [string]: vector },
	lowered: { [string]: number },
	plain: { [string]: number }
): string?
	local loweredCounts: { [string]: number }, halved: number = drive(tweak, places, UNDER_LOAD)
	local plainCounts: { [string]: number }, unhalved: number = drive(tweak, places, nil)

	if halved < COUNTED or unhalved ~= 0 then
		return `{name}: the far rate under load lowered {halved} runs, and {unhalved} with none`
	end

	for body: string, expected: number in lowered do
		if loweredCounts[body] ~= expected then
			return `{name}: with the farthest band lowered the {body} records came {loweredCounts[body]}, not {expected}`
		elseif plainCounts[body] ~= plain[body] then
			return `{name}: with no far rate under load the {body} records came {plainCounts[body]}, not {plain[body]}`
		end
	end

	return nil
end

return function (): (boolean, string | nil)
	local why: string? = compare("Out of view", nil, CONE, CONE_LOWERED, CONE_PLAIN)
		or compare("Crowd", capped, CAPPED, CAPPED_LOWERED, CAPPED_PLAIN)
	if why then
		return false, why
	end

	return true, nil
end
