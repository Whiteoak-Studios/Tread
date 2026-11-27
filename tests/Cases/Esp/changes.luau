--[[
    A change record moves its slot's box to the record it rebuilds against
    the one its base names, across the u16 tick wrap, and one naming a
    record the ESP never heard is left out while the block's others go on
--]]

--!strict
local Changes = require("../../Fixtures/Interpolate/Changes")
local Rig = require("../../Fixtures/Esp/Rig")

local MOVER: number = 3 -- Sent as changes once revealed
local OTHER: number = 4 -- Sent whole
local GENERATION: number = 1
local TICK: number = 65534 -- Two relay ticks short of the u16 wrap
local WIRE: number = 2 ^ 16
local FRAMES: number = 3
local CLOSE: number = 1e-3 -- Studs a placed value may differ by, since a part holds float32
local START: vector = vector.create(100.5, 5.25, -200.75)
local ASIDE: vector = vector.create(10, 0, 0) -- Where OTHER stands from START

local function record(slot: number, at: vector): buffer
	return Changes.record({ slot = slot, generation = GENERATION, position = at })
end

local function near(a: any, b: vector): boolean
	return math.abs(a.X - b.x) < CLOSE and math.abs(a.Y - b.y) < CLOSE and math.abs(a.Z - b.z) < CLOSE
end

return function (): (boolean, string | nil)
	local rig: any = Rig.new()
	local step: any = rig.shared.step
	local switch: (on: boolean) -> () = rig.startEsp()

	rig.slots({
		{ slot = MOVER, generation = GENERATION, rig = "A" },
		{ slot = OTHER, generation = GENERATION, rig = "A" },
	})
	switch(true)

	-- Where a standing hull's center sits over its feet
	local function center(at: vector): vector
		return at + vector.create(0, step.standing / 2, 0)
	end

	local first: buffer = record(MOVER, START)
	rig.send(
		"Relay",
		Changes.block({
			sequence = 1,
			tick = TICK,
			reveals = {
				{ slot = MOVER, generation = GENERATION, kind = "Player" },
				{ slot = OTHER, generation = GENERATION, kind = "Player" },
			},
			records = { first, record(OTHER, START + ASIDE) },
		})
	)
	rig.frames(FRAMES)

	-- 1) Past the wrap, 3 relay ticks on, a change against the first record moves its box
	local moved: vector = START + vector.create(1.5, 0, -0.75)
	rig.send(
		"Relay",
		Changes.block({
			sequence = 2,
			tick = (TICK + 3) % WIRE,
			changes = { Changes.change(record(MOVER, moved), first, 3) },
		})
	)
	rig.frames(FRAMES)

	local anchor: any = rig.slot(MOVER)
	if not anchor or not near(anchor.CFrame.Position, center(moved)) then
		return false, `The changed slot's box sits at {anchor and anchor.CFrame.Position}, not over {moved}`
	elseif not string.find(rig.count().Text, "1 slots", 1, true) then
		return false, `The count reads "{rig.count().Text}" after a block of one change`
	end

	-- 2) A change naming the tick between, which carried nothing, is left out, and the whole record beside it drawn
	local stray: vector = START + vector.create(40, 0, 0)
	local walked: vector = START + ASIDE + vector.create(0, 0, 5)
	rig.send(
		"Relay",
		Changes.block({
			sequence = 3,
			tick = (TICK + 4) % WIRE,
			records = { record(OTHER, walked) },
			changes = { Changes.change(record(MOVER, stray), record(MOVER, moved), 2) },
		})
	)
	rig.frames(FRAMES)

	local otherAnchor: any = rig.slot(OTHER)
	if not near(rig.slot(MOVER).CFrame.Position, center(moved)) then
		return false, `A change with no baseline heard moved its box to {rig.slot(MOVER).CFrame.Position}`
	elseif not otherAnchor or not near(otherAnchor.CFrame.Position, center(walked)) then
		return false, `The whole record beside it left its box at {otherAnchor and otherAnchor.CFrame.Position}`
	elseif not string.find(rig.count().Text, "2 slots", 1, true) then
		return false, `The count reads "{rig.count().Text}", not the block's record and change`
	end

	switch(false)

	return true, nil
end
