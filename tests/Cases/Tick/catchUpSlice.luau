--[[
    A Heartbeat that runs two ticks to catch up runs each between stage
    once, in its place in the first tick and handed that tick, while every
    other stage runs in both, and a frame past the catch-up does the same
--]]

--!strict
local Environment = require("../../Environment")
local Frames = require("../../Fixtures/Server/Frames")

local GLOBALS: string = "tests/Fixtures/Environment/Globals.luau"
local RATE: number = 20
local CATCH_UP: number = 2
local HALF: number = 0.5 -- A tick's share past each frame's whole ticks, so none lands on a tick's edge
local OWED: number = 2 -- Whole ticks of time the first long frame owes, the catch-up's
local STALL: number = 5 -- And the second, past the catch-up

return function (): (boolean, string | nil)
	local globals: any = Environment.load(GLOBALS)
	local frames: Frames.Frames = Frames.new(globals)
	local Tick: any = globals.require(globals.game:GetService("ReplicatedStorage").Packages.Tread.Server.Tick)

	local order: { string } = {}
	local function stage(name: string, between: boolean): { name: string, between: boolean, run: (tick: number) -> () }
		return {
			name = name,
			between = between,
			run = function (tick: number)
				table.insert(order, `{name} {tick}`)
			end,
		}
	end

	Tick.start(RATE, CATCH_UP, { stage("before", false), stage("slices", true), stage("after", false) })

	frames:run((OWED + HALF) / RATE)

	local ran: string = table.concat(order, ", ")
	if ran ~= "before 1, slices 1, after 1, before 2, after 2" then
		return false, `A frame owing {OWED} ticks ran {ran}`
	end

	table.clear(order)
	frames:run(STALL / RATE)

	ran = table.concat(order, ", ")
	local _, dropped: number = Tick.counts()
	if ran ~= "before 3, slices 3, after 3, before 4, after 4" or dropped ~= STALL - CATCH_UP then
		return false, `A frame owing {STALL} ticks ran {ran} and dropped {dropped}`
	end

	local slices: any = Tick.stages()[2]
	if slices.held ~= 2 then
		return false, `The between stage's ring holds {slices.held} times after two Heartbeats, not one each`
	end

	return true, nil
end
