--[[
    reason gives why a pair is sent or held back: untested before its first
    test, clear on an open ray, held through the hold, hidden past it, failed
    open untested, an NPC and a teammate never tested, and it changes nothing
--]]

--!strict
local Environment = require("../../Environment")

local HARNESS: string = "tests/Fixtures/AntiEsp/Harness.luau"
local TEAM: number = 4
local STARVED: number = 0 -- A slice budget with no time to test anything

-- Each slice's time, whether its walls block, and what the player pair's reason is after it, from the example's 1 s
-- hold, its 2 Hz and 10 Hz rechecks and its 0.15 s fail-open, the last two slices starved
local STEPS: { { any } } = {
	{ 0, false, "Clear", 1 },
	{ 0.5, true, "Hold", 1 },
	{ 1, true, "Hold", 1 },
	{ 1.5, true, "Hidden", 1 },
	{ 1.6, true, "Hidden", STARVED },
	{ 1.7, true, "FailOpen", STARVED },
	{ 1.8, true, "Hidden", 1 },
}

return function (): (boolean, string | nil)
	local Harness: any = Environment.load(HARNESS)
	local harness: any = Harness.new()
	local AntiEsp: any = Harness.AntiEsp

	local own: number, viewer: any = harness:player("Viewer", vector.zero)
	local target: number = harness:body("Player", vector.create(0, 0, -50))
	local npc: number = harness:body("Npc", vector.create(0, 0, -60))
	local mate: number = harness:body("Player", vector.create(10, 0, -50))
	local sleeper: number = harness:body("Sleeper", vector.create(-10, 0, -50))

	AntiEsp.setTeam(own, TEAM)
	AntiEsp.setTeam(mate, TEAM)

	if AntiEsp.reason(viewer.key, target) ~= "Untested" then
		return false, "A pair anti-ESP was never asked about had a reason other than Untested"
	elseif AntiEsp.reason(viewer.key, npc) ~= "Npc" then
		return false, "An NPC's reason was not Npc before anyone asked"
	end

	local function ask()
		for _, slot: number in { target, npc, mate, sleeper } do
			AntiEsp.isHidden(viewer, slot)
		end
	end

	ask()

	local first: { [number]: string } =
		{ [target] = "Untested", [npc] = "Npc", [mate] = "Teammate", [sleeper] = "Untested" }
	for slot: number, reason: string in first do
		local given: string = AntiEsp.reason(viewer.key, slot)
		if given ~= reason then
			return false, `Slot {slot}'s reason was {given} before any test, not {reason}`
		end
	end

	for index: number, step: { any } in STEPS do
		local now: number, walls: boolean, reason: string, budget: number = step[1], step[2], step[3], step[4]

		if walls then
			harness.wall = Harness.solid
		else
			harness.wall = Harness.open
		end

		harness:slice(now, budget)
		ask()

		local given: string = AntiEsp.reason(viewer.key, target)
		local hidden: boolean = reason == "Hidden"
		if given ~= reason then
			return false, `After slice {index} at {now} s the pair's reason was {given}, not {reason}`
		elseif AntiEsp.isHidden(viewer, target) ~= hidden then
			return false, `After slice {index} at {now} s the pair's reason {given} disagreed with isHidden`
		end
	end

	-- The sleeper's first test found its rays open, and its schedule keeps that verdict
	if AntiEsp.reason(viewer.key, sleeper) ~= "Clear" then
		return false, `The sleeper's reason was {AntiEsp.reason(viewer.key, sleeper)}, not Clear`
	elseif AntiEsp.reason(viewer.key, mate) ~= "Teammate" or AntiEsp.reason(viewer.key, npc) ~= "Npc" then
		return false, "A teammate's or an NPC's reason changed once tests ran"
	end

	-- Asking changes nothing anti-ESP counts
	local tests: number, hidden: number, failOpens: number = AntiEsp.counts()
	for _ = 1, 10 do
		AntiEsp.reason(viewer.key, target)
	end

	local afterTests: number, afterHidden: number, afterFailOpens: number = AntiEsp.counts()
	if afterTests ~= tests or afterHidden ~= hidden or afterFailOpens ~= failOpens then
		return false, "Asking a reason changed anti-ESP's counts"
	elseif pcall(AntiEsp.reason, viewer.key, -1) then
		return false, "reason took a value that is no slot"
	end

	return true, nil
end
