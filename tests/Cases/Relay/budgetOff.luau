--[[
    With no relay budget set, every pinned layout gives its digest in process
    and on 2 stand-in workers, and the relay never reads its clock, as each
    layout's own workers case runs it on other counts with the same clock
--]]

--!strict
local Layouts = require("../../Fixtures/Relay/Layouts")

local WORKERS: { number } = { 2 }

type Result = Layouts.Result

-- Each pinned layout by its name in Layouts.EXPECTED
local LAYOUTS: { [string]: (workers: number?) -> Result } = {
	idle = Layouts.idle,
	fight = Layouts.fight,
	field = Layouts.field,
	taps = Layouts.taps,
	bands = Layouts.bands,
	crowd = Layouts.crowd,
}

-- Why a layout's run gave other than its pinned digest or read the clock, or nil when it did neither
local function judge(name: string, result: Result, where: string): string?
	if result.digest ~= Layouts.EXPECTED[name] then
		return `The {name} layout {where} digests to {result.digest}, not {Layouts.EXPECTED[name]}`
	elseif result.reads ~= 0 then
		return `The {name} layout {where} read the relay's clock {result.reads} times with no budget set`
	end

	return nil
end

return function (): (boolean, string | nil)
	for name: string, layout: (workers: number?) -> Result in LAYOUTS do
		local why: string? = judge(name, layout(nil), "in process")
		if why then
			return false, why
		end

		for _, workers: number in WORKERS do
			why = judge(name, layout(workers), `on {workers} workers`)
			if why then
				return false, why
			end
		end
	end

	return true, nil
end
