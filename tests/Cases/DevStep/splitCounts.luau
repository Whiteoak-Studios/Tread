--[[
    The split by stage over a window's Heartbeat flags: a tick deferred for
    each Heartbeat that ran a deferred tick's rest, and a fallback for each
    tick run whole right after one that deferred, the newest neither
--]]

--!strict
local Window = require("../../Fixtures/DevStep/Window")

local TREAD: number = 0.001 -- Seconds of Tread's work in each Heartbeat of a hand-built readout

-- One window's flags, what it shows, and its ticks deferred and fallbacks, worked by hand from Tick's flags: TICKED 1,
-- HELD 2, POLLED 4, RELEASED 8 and DEFERRED 16
type Row = { name: string, flags: { number }, deferred: number, fallbacks: number }

local ROWS: { Row } = {
	{
		-- Two calm deferrals, each its tick alone, its rest dispatching and held, its poll releasing it, then a tick
		-- run whole and held, released at the next Heartbeat, and a Heartbeat with nothing
		name = "two deferrals and a whole tick",
		flags = { 1, 18, 12, 1, 18, 12, 3, 12, 0 },
		deferred = 2,
		fallbacks = 1,
	},
	{
		-- A tick owed on the rest's Heartbeat skips that rest and runs whole there, holding its own round
		name = "a skipped rest",
		flags = { 1, 19, 12, 0 },
		deferred = 1,
		fallbacks = 1,
	},
	{
		-- The split off: every tick whole, so nothing defers and nothing falls back
		name = "the split off",
		flags = { 3, 12, 0, 3, 12, 0 },
		deferred = 0,
		fallbacks = 0,
	},
	{
		-- The newest tick has no Heartbeat after it, so it is neither deferred nor whole
		name = "a tick at the window's end",
		flags = { 1, 18, 12, 1 },
		deferred = 1,
		fallbacks = 0,
	},
}

return function (): (boolean, string | nil)
	local Run: any = Window.run()

	for _, row: Row in ROWS do
		local deferred: number, fallbacks: number = Run.deferrals(row.flags)
		if deferred ~= row.deferred or fallbacks ~= row.fallbacks then
			local wanted: string = `{row.deferred} and {row.fallbacks}`
			return false, `With {row.name}, the split read {deferred} deferred and {fallbacks} fallbacks, not {wanted}`
		end
	end

	-- A window's figures carry both, and one with no Heartbeat neither
	local flags: { number } = ROWS[1].flags
	local taken: any = Window.taken()
	taken.readout = {
		times = table.create(#flags, TREAD),
		flags = flags,
		bots = table.create(#flags, 0),
		through = #flags,
		lost = 0,
	}

	local figures: { [string]: number } = Run.figures(taken)
	if figures.deferred ~= 2 or figures.fallbacks ~= 1 then
		return false, `The window's figures read {figures.deferred} deferred and {figures.fallbacks} fallbacks`
	end

	taken.readout = { times = {}, flags = {}, bots = {}, through = 0, lost = 0 }
	local empty: { [string]: number } = Run.figures(taken)
	if empty.deferred ~= nil or empty.fallbacks ~= nil then
		return false, "A window with no Heartbeat carried the split's figures"
	end

	return true, nil
end
