--[[
    The noise run puts the session's levers back as it found them however
    it ends, a throw in its header, in a half or in a table among them, and
    fails with a line naming the throw
--]]

--!strict
local Step = require("../../Fixtures/DevStep/Step")

local THREW: string = "Step benchmark noise run threw: "

-- A line whose text can't be read, as a half's line a run could never use
local UNREADABLE: any = setmetatable({}, {
	__tostring = function (): string
		error("a stand-in line that can't be read", 0)
	end,
})

-- Each half drives and gives its figures, its line, or both as the case breaks them
local function answers(line: any, figures: any): Step.Answer
	return function (_: string, _: string?): (boolean, string, { [string]: number }?)
		return true, line, figures
	end
end

-- Whether step 3's caps stand as each run here starts them, the other way from the dev server: anti-ESP's slice not
-- whole, no NPC budget, no relay budget and no far rate under load, with step 1's and step 2's levers on as the server
-- starts them, verdict memory and the split off
local function opposite(mounted: Step.Mounted): boolean
	return not mounted.AntiEsp.wholeOn()
		and mounted.Npcs.budget() == nil
		and mounted.Relay.budget() == nil
		and mounted.Relay.underLoad() == nil
		and #mounted.Relay.bands() == 3
		and mounted.Relay.crowd() ~= nil
		and mounted.Commands.lazyOn()
		and mounted.Characters.checksOn()
		and not mounted.AntiEsp.memoryOn()
		and not mounted.Tick.splitOn()
end

-- A mount whose caps start the other way from the dev server's, so a noise run must set each and put it back
local function mount(answer: Step.Answer): Step.Mounted
	local mounted: Step.Mounted = Step.load(answer)
	Step.capsOff(mounted)

	return mounted
end

return function (): (boolean, string | nil)
	local figures: { [string]: number } = { skipped = 1 }
	local breaks: { { what: string, mounted: Step.Mounted, thrown: string } } = {}

	-- 1) The header throws: the server's settings hold no anti-ESP table to read the workers made from
	local header: Step.Mounted = mount(answers("drove and cleaned up", figures))
	header.settings.antiEsp = nil
	table.insert(breaks, { what = "header", mounted = header, thrown = "workers" })

	-- 2) A half throws past its run: its line can't be read
	local half: Step.Mounted = mount(answers(UNREADABLE, figures))
	table.insert(breaks, { what = "half", mounted = half, thrown = "a stand-in line that can't be read" })

	-- 3) A table throws: a figure it can't print
	local broken: Step.Mounted = mount(answers("drove and cleaned up", { skipped = "many" }))
	table.insert(breaks, { what = "table", mounted = broken, thrown = "Compare.luau" })

	for _, case: { what: string, mounted: Step.Mounted, thrown: string } in breaks do
		local mounted: Step.Mounted = case.mounted
		if not opposite(mounted) then
			return false, `Before the run whose {case.what} throws, its levers didn't stand the other way`
		end

		local passed: boolean, reason: string? = mounted.BenchStepNoise()
		local text: string = reason or ""
		local at: number? = string.find(text, THREW, 1, true)

		if passed then
			return false, `A noise run whose {case.what} threw passed`
		elseif not at or not string.find(text, case.thrown, at, true) then
			return false, `A noise run whose {case.what} threw gave:\n{text}`
		elseif not opposite(mounted) then
			return false, `A noise run whose {case.what} threw left its levers other than as it found them`
		end
	end

	-- The half and the table each threw after its run had set the levers on: the halves asked ran with them on
	for _, mounted: Step.Mounted in { half, broken } do
		local asked: Step.Asked? = mounted.asked[1]
		local caps: boolean = asked ~= nil
			and asked.whole
			and asked.npcBudget ~= nil
			and asked.relayBudget ~= nil
			and asked.underLoad ~= nil
		if not caps then
			return false, "A noise run that threw later ran its first half without the session's levers on"
		end
	end

	return true, nil
end
