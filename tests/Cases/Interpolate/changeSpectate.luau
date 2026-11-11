--[[
    Across a spectate's start and its end, a change naming a record from
    before the new view's tick is dropped and its block left unacknowledged,
    though the view before sent a record at that tick, while a change
    against the new view's own records rebuilds
--]]

--!strict
local Changes = require("../../Fixtures/Interpolate/Changes")
local Viewer = require("../../Fixtures/Interpolate/Viewer")

local SLOT: number = 5
local GENERATION: number = 1
local OWN: number = 10 -- The moderator's own view's first tick
local TARGET: number = 12 -- The tick the spectate's view starts at
local BACK: number = 16 -- The tick the moderator's own view starts at again
local TARGET_SEQUENCE: number = 500 -- The target's own sequences, which the moderator acknowledges while it spectates
local FRAME: number = 0.05 -- Seconds a frame, one relay tick at 20 Hz
local AFTER: number = 10 -- Frames drawn past the last block, so the render time passes every record
local START: vector = vector.create(0, 5, 0)
local STRIDE: number = 0.5 -- Studs it moves a relay tick
local REVEAL: { any } = { { slot = SLOT, generation = GENERATION, kind = "Player" } }

-- Each step: a block's sequence and tick, whether it reveals the slot, its change's base or nil for a whole record, and
-- whether this client acknowledges it; or a restart at its tick
type Step = {
	restart: number?,
	sequence: number?,
	tick: number?,
	reveal: boolean?,
	base: number?,
	acknowledged: boolean?,
}

local STEPS: { Step } = {
	{ sequence = 1, tick = OWN, reveal = true, acknowledged = true },
	{ sequence = 2, tick = OWN + 1, acknowledged = true },
	{ restart = TARGET },
	{ sequence = TARGET_SEQUENCE, tick = TARGET, reveal = true, acknowledged = true },
	{ sequence = TARGET_SEQUENCE + 1, tick = TARGET + 1, base = 2, acknowledged = false }, -- Names OWN + 1, the view before's
	{ sequence = TARGET_SEQUENCE + 2, tick = TARGET + 2, base = 2, acknowledged = true }, -- Names TARGET
	{ restart = BACK },
	{ sequence = 3, tick = BACK, reveal = true, acknowledged = true },
	{ sequence = 4, tick = BACK + 1, base = 3, acknowledged = false }, -- Names TARGET + 2, the spectate's
	{ sequence = 5, tick = BACK + 2, base = 2, acknowledged = true }, -- Names BACK
}

local function record(tick: number): buffer
	local at: vector = START + vector.create(0, 0, (tick - OWN) * STRIDE)

	return Changes.record({ slot = SLOT, generation = GENERATION, position = at })
end

return function (): (boolean, string | nil)
	-- The moderator sent the changes, and one sent the records whole, those it can't rebuild left out
	local changed = Viewer.new()
	local whole = Viewer.new()
	changed.announce(SLOT, GENERATION, "A")
	whole.announce(SLOT, GENERATION, "A")

	-- Draws a frame on both, and why the slot isn't drawn alike on them, or nil when it is
	local function frame(when: string): string?
		changed.Interpolate.frame(FRAME)
		whole.Interpolate.frame(FRAME)

		local drawn: boolean, state: any = changed.pose(SLOT)
		local wholeDrawn: boolean, wholeState: any = whole.pose(SLOT)
		if drawn ~= wholeDrawn or (drawn and state.position ~= wholeState.position) then
			return `{when}, the slot was drawn at {drawn and state.position}, not {wholeState.position}`
		end

		return nil
	end

	local newest: number = 0
	local mask: number = 0

	for index: number, step: Step in STEPS do
		local restart: number? = step.restart
		if restart then
			changed.Interpolate.restart(restart)
			whole.Interpolate.restart(restart)
			newest, mask = 0, 0

			continue
		end

		local sequence: number = step.sequence :: number
		local tick: number = step.tick :: number
		local base: number? = step.base
		local reveals: { any }? = nil
		if step.reveal then
			reveals = REVEAL
		end

		if base then
			local change: buffer = Changes.change(record(tick), record(tick - base), base)
			changed.Interpolate.receive(
				Changes.block({ sequence = sequence, tick = tick, reveals = reveals, changes = { change } })
			)
		else
			changed.Interpolate.receive(
				Changes.block({ sequence = sequence, tick = tick, reveals = reveals, records = { record(tick) } })
			)
		end

		local records: { buffer } = {}
		if step.acknowledged then
			table.insert(records, record(tick))
		end

		whole.Interpolate.receive(
			Changes.block({ sequence = sequence, tick = tick, reveals = reveals, records = records })
		)

		-- 1) Acknowledged exactly when its change was rebuilt, from the view's first block
		if step.acknowledged and newest == 0 then
			newest, mask = sequence, 0
		elseif step.acknowledged then
			local ahead: number = sequence - newest
			mask = bit32.bor(bit32.lshift(mask, ahead), bit32.lshift(1, ahead - 1))
			newest = sequence
		end

		local acknowledged: number, bits: number = changed.Interpolate.received()
		if acknowledged ~= newest or bits ~= mask then
			return false,
				`Step {index}, at tick {tick}, left the acknowledgment at {acknowledged} with {bits}, not {newest} with {mask}`
		end

		-- 2) Drawn as the records sent whole are, then and past the last block
		local why: string? = frame(`After step {index}, at tick {tick}`)
		if why then
			return false, why
		end
	end

	for _ = 1, AFTER do
		local why: string? = frame("Past the last block")
		if why then
			return false, why
		end
	end

	-- 3) Each restart closed the slot and each view's reveal opened it again, alike for both
	if #changed.hides ~= 2 or #changed.reveals ~= 3 or #whole.hides ~= 2 or #whole.reveals ~= 3 then
		return false, `The views told {#changed.reveals} reveals and {#changed.hides} hides, not 3 and 2`
	end

	return true, nil
end
