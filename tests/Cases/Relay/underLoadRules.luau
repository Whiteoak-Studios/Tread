--[[
    While the far rate under load holds the farthest band lowered, every
    record there is lowered alike: a player in view as the crowd cap's rest,
    one held to the out-of-view rate and an enemy a moderator is sent
    withheld; a shooter's raise, a zoomed viewer's rates, a nearer band and
    an NPC's rate are not
--]]

--!strict
local Bands = require("../../Fixtures/Relay/Bands")
local Environment = require("../../Environment")

local HARNESS: string = "tests/Fixtures/Relay/Harness.luau"
local BUDGET: number = 1 -- Stand-in seconds, which every run's one read of STEP passes, three viewers leaving none
local STEP: number = 2
local UNDER_LOAD: { runs: number, scale: number } = { runs = 1, scale = 0.5 } -- Lowered from the second run on
local CROWD: { size: number, rate: number, floor: number } = { size = 1, rate = 20, floor = 5 }
local SETTLE: number = 4 -- Runs before the count, past the reveals and the lowering
local COUNTED: number = 40 -- Runs counted, a whole number of each rate's period
local STRIDE: number = 0.1 -- Studs every body moves a run, back and forth, so each always has a change to send
local LOOK: vector = vector.create(0, 0, -1)
local TARGET_AT: vector = vector.create(2000, 0, 2000) -- A watched viewer far from the rest, and its enemy 800 off
local ENEMY_AT: vector = vector.create(2000, 0, 1200)

-- Each body's place, the seated viewer at the origin looking along -Z: the crowd cap's one member near, a player in
-- view, one behind and one to the side who shoots near the viewer, all three in the farthest band, and an NPC past
-- npcs.near
local PLACES: { [string]: vector } = {
	member = vector.create(0, 0, -50),
	ahead = vector.create(0, 0, -800),
	behind = vector.create(0, 0, 800),
	shooter = vector.create(800, 0, 0),
	npc = vector.create(0, 0, -300),
}

-- Records over the counted runs with the farthest band lowered, and with no far rate under load: the farthest band's
-- 5 Hz halved to 2.5 for the rest, the out-of-view player and the withheld enemy; the shooter's 10 Hz raise, the zoomed
-- viewer's 20 Hz and the member's first band kept; the NPC's rate kept, compared with itself
local LOWERED: { [string]: number } = { ahead = 5, behind = 5, withheld = 5, shooter = 20, zoomed = 40, member = 40 }
local PLAIN: { [string]: number } = { ahead = 10, behind = 10, withheld = 10, shooter = 20, zoomed = 40, member = 40 }

local function tweak(shared: any, server: any)
	Bands.three(shared, server)
	server.tiers.crowd = table.clone(CROWD)
end

-- Each body's records over the counted runs, with or without the far rate under load
local function drive(underLoad: { runs: number, scale: number }?): { [string]: number }
	local Harness: any = Environment.load(HARNESS)
	local harness: any = Harness.new(nil, tweak)

	local seated: any = harness:viewer("Seated")
	seated.viewer.slot = harness:spawn("Player", vector.zero)
	seated.viewer.look = LOOK

	local zoomed: any = harness:viewer("Zoomed")
	zoomed.viewer.zoomed = true

	local watched: any = harness:viewer("Watched")
	watched.viewer.position = TARGET_AT
	local moderator: any = harness:viewer("Moderator")
	moderator.viewer.position = TARGET_AT
	harness:watch(moderator, watched)

	local slots: { [string]: number } = {}
	for name: string, at: vector in PLACES do
		slots[name] = harness:spawn(name == "npc" and "Npc" or "Player", at)
	end

	local enemy: number = harness:spawn("Player", ENEMY_AT)
	harness:hide(watched, enemy, true)

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

		harness.states[enemy].position += vector.create(step, 0, 0)

		-- The shot near the viewer raises the shooter for the example's 5 s, past every counted run
		if run == SETTLE then
			Harness.Relay.shotNear(seated.viewer.key, slots.shooter)
		end

		harness:run()

		if run > SETTLE then
			for name: string, slot: number in slots do
				counts[name] = (counts[name] or 0) + Harness.count(seated.seen.records, slot)
			end

			local withheld: { any } = Harness.withheld(moderator)
			counts.withheld = (counts.withheld or 0) + Harness.count(withheld, enemy)
			counts.zoomed = (counts.zoomed or 0) + Harness.count(zoomed.seen.records, slots.ahead)
		end
	end

	return counts
end

return function (): (boolean, string | nil)
	local lowered: { [string]: number } = drive(UNDER_LOAD)
	local plain: { [string]: number } = drive(nil)

	for name: string, expected: number in LOWERED do
		if lowered[name] ~= expected then
			return false, `With the farthest band lowered the {name} records came {lowered[name]}, not {expected}`
		elseif plain[name] ~= PLAIN[name] then
			return false, `With no far rate under load the {name} records came {plain[name]}, not {PLAIN[name]}`
		end
	end

	if lowered.npc ~= plain.npc or lowered.npc == 0 then
		return false, `The NPC sent {lowered.npc} records with the band lowered and {plain.npc} without`
	end

	return true, nil
end
