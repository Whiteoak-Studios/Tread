--[[
    The NPC steps a budget made wait and the viewer turns relay.budget left
    are sums over a window's reads, so a cap that acts in only a few reads
    still prints its row, and no read's count is taken as a rate
--]]

--!strict
local Harness = require("../../Fixtures/DevServer/Harness")
local Window = require("../../Fixtures/DevStep/Window")

local HALVES: { string } = { "before", "after" }

-- Seven reads of an after half whose caps acted now and then: viewers left in two of them, NPCs made to wait in one,
-- so each count's median over the reads is 0
local LEFT: { number } = { 0, 0, 9, 0, 0, 3, 0 }
local WAITED: { number } = { 0, 4, 0, 0, 0, 0, 0 }
local NONE: { number } = { 0, 0, 0, 0, 0, 0, 0 } -- A before half's, with the caps off

-- Worked by hand: 9 + 3 turns left and 4 steps made to wait, against 0 before, with no percent over a before of 0
local LEFT_SUM: number = 12
local WAITED_SUM: number = 4
local ROWS: { string } = {
	"\nNPC steps made to wait: 0 4 +4 n/a\n",
	"\nviewer turns relay.budget left: 0 12 +12 n/a\n",
}

-- A window's figures with the two counts' samples given
local function figuresOf(Run: any, left: { number }, waited: { number }): { [string]: number }
	local taken: any = Window.taken()
	taken.samples.relayLeft = table.clone(left)
	taken.samples.npcsWaited = table.clone(waited)

	return Run.figures(taken)
end

return function (): (boolean, string | nil)
	local Run: any = Window.run()
	local loaded: Harness.Loaded = Harness.load()
	local Compare: any = loaded.require(loaded.game:GetService("ServerScriptService").Server.Bots.Compare)

	-- 1) A read's counts become no rate: reads carrying only the two counts and their divisors push nothing
	local rates: { [string]: { number } } = {}
	for index: number = 1, #LEFT do
		Run.counts({ ticks = 20, relaySkipped = 4, relayLeft = LEFT[index], npcsWaited = WAITED[index] }, rates)
	end

	local pushed: string? = next(rates)
	if pushed ~= nil then
		return false, `The reads pushed {pushed} as a rate`
	end

	-- 2) The window's figures are each count summed over its reads
	local after: { [string]: number } = figuresOf(Run, LEFT, WAITED)
	if after.relayLeft ~= LEFT_SUM or after.npcsWaited ~= WAITED_SUM then
		local read: string = `{after.relayLeft} turns left and {after.npcsWaited} steps made to wait`
		return false, `The window read {read}, not {LEFT_SUM} and {WAITED_SUM}`
	end

	-- 3) The table prints both rows, though the caps acted in fewer than half the after half's reads
	local before: { [string]: number } = figuresOf(Run, NONE, NONE)
	local text: string = Compare.table("S4", HALVES, before, after)
	for _, row: string in ROWS do
		if not string.find(text, row, 1, true) then
			return false, `The table has no row{row}in:\n{text}`
		end
	end

	-- And with both halves at 0 neither row prints
	local quiet: string = Compare.table("S4", HALVES, before, before)
	if string.find(quiet, "made to wait", 1, true) or string.find(quiet, "relay.budget left", 1, true) then
		return false, `With both halves at 0, the table kept a cap's row:\n{quiet}`
	end

	return true, nil
end
