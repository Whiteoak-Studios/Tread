--[[
    A zoomed viewer gets moving players in view in the second and third bands
    at the first band's 20 a second, one behind it at the out-of-view rate and
    an NPC at its own, while a viewer beside it gets them at their bands' rates
--]]

--!strict
local Bands = require("../../Fixtures/Relay/Bands")
local Environment = require("../../Environment")

local HARNESS: string = "tests/Fixtures/Relay/Harness.luau"
local RUNS: number = 40 -- Two seconds at the example's 20 Hz relay
local SETTLE: number = 4 -- Runs before the count starts, past each target's reveal
local STRIDE: number = 0.1 -- Studs each target moves a run, back and forth, so each always has a change to send
local BESIDE: vector = vector.create(4, 0, 0) -- Where the viewer not zoomed stands, its targets in the same bands

-- Each target by where it stands: two players ahead in the second and third bands, one behind in the second, and an
-- NPC ahead past npcs.near, with the records each viewer got of it
type Target = { name: string, kind: string, at: vector, zoomed: number, plain: number }

local TARGETS: { Target } = {
	{ name = "second band", kind = "Player", at = vector.create(0, 0, -450), zoomed = 40, plain = 20 },
	{ name = "third band", kind = "Player", at = vector.create(0, 0, -800), zoomed = 40, plain = 10 },
	{ name = "behind", kind = "Player", at = vector.create(0, 0, 450), zoomed = 10, plain = 10 },
	{ name = "NPC", kind = "Npc", at = vector.create(0, 0, -300), zoomed = 4, plain = 4 },
}

return function (): (boolean, string | nil)
	local Harness: any = Environment.load(HARNESS)
	local harness: any = Harness.new(nil, Bands.three)

	-- Both facing along -Z
	local zoomed: any = harness:viewer("Zoomed")
	zoomed.viewer.slot = harness:spawn("Player", vector.zero)
	zoomed.viewer.zoomed = true

	local plain: any = harness:viewer("Plain")
	plain.viewer.slot = harness:spawn("Player", BESIDE)
	plain.viewer.position = BESIDE

	local slots: { number } = {}
	for index: number, target: Target in TARGETS do
		slots[index] = harness:spawn(target.kind, target.at)
	end

	local zoomedCounts: { number } = table.create(#TARGETS, 0)
	local plainCounts: { number } = table.create(#TARGETS, 0)
	for run: number = 1, SETTLE + RUNS do
		local step: number = STRIDE
		if run % 2 == 0 then
			step = -STRIDE
		end

		for _, slot: number in slots do
			harness.states[slot].position += vector.create(step, 0, 0)
		end

		harness:run()

		if run > SETTLE then
			for index: number, slot: number in slots do
				zoomedCounts[index] += Harness.count(zoomed.seen.records, slot)
				plainCounts[index] += Harness.count(plain.seen.records, slot)
			end
		end
	end

	local got: string = `zoomed {table.concat(zoomedCounts, ", ")} and not {table.concat(plainCounts, ", ")}`
	for index: number, target: Target in TARGETS do
		if zoomedCounts[index] ~= target.zoomed then
			return false, `The zoomed viewer got {zoomedCounts[index]} records of the {target.name} target ({got})`
		elseif plainCounts[index] ~= target.plain then
			return false, `The viewer not zoomed got {plainCounts[index]} records of the {target.name} target ({got})`
		end
	end

	return true, nil
end
