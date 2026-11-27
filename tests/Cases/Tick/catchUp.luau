--[[
    A Heartbeat runs the whole ticks its time owes up to the catch-up, drops
    and counts the rest, and keeps the fraction of a tick left over, so two
    short frames make one tick between them; each stage is handed the tick's
    number, counted on from 1
--]]

--!strict
local Environment = require("../../Environment")
local Frames = require("../../Fixtures/Server/Frames")

local GLOBALS: string = "tests/Fixtures/Environment/Globals.luau"
local RATE: number = 20
local CATCH_UP: number = 2
local STALL: number = 10 -- Ticks of time one long frame owes
local SHORT: number = 0.6 -- A tick's share one short frame owes
local SHORTER: number = 0.5 -- And the next, which with it passes a whole tick

return function (): (boolean, string | nil)
	local globals: any = Environment.load(GLOBALS)
	local frames: Frames.Frames = Frames.new(globals)
	local Tick: any = globals.require(globals.game:GetService("ReplicatedStorage").Packages.Tread.Server.Tick)

	local ticks: { number } = {}
	Tick.start(RATE, CATCH_UP, {
		{
			name = "count",
			run = function (tick: number)
				table.insert(ticks, tick)
			end,
		},
	})

	frames:run(STALL / RATE)

	local ran: number, dropped: number = Tick.counts()
	if #ticks ~= CATCH_UP or ran ~= CATCH_UP or dropped ~= STALL - CATCH_UP then
		return false,
			`A frame owing {STALL} ticks ran {#ticks} and dropped {dropped}, not {CATCH_UP} and {STALL - CATCH_UP}`
	elseif ticks[1] ~= 1 or ticks[2] ~= 2 then
		return false, `The ticks run were numbered {ticks[1]} and {ticks[2]}, not 1 and 2`
	end

	frames:run(SHORT / RATE)
	if #ticks ~= CATCH_UP then
		return false, "A frame owing less than a tick ran one"
	end

	frames:run(SHORTER / RATE)

	ran, dropped = Tick.counts()
	if #ticks ~= CATCH_UP + 1 or ticks[#ticks] ~= CATCH_UP + 1 or dropped ~= STALL - CATCH_UP then
		return false, `Two short frames passing a tick between them ran {#ticks - CATCH_UP} ticks and dropped {dropped}`
	end

	return true, nil
end
