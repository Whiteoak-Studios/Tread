--[[
    Each stage keeps its time for every tick of the last 10 s, its newest
    as its last, and no more once the ring is full
--]]

--!strict
local Environment = require("../../Environment")
local Frames = require("../../Fixtures/Server/Frames")

local GLOBALS: string = "tests/Fixtures/Environment/Globals.luau"
local RATE: number = 20
local CATCH_UP: number = 2
local WINDOW: number = 10 * RATE -- Ticks in the 10 s each stage's times cover
local PAST: number = 5 -- Ticks run past the window's
local WORK: number = 1000 -- Additions the stage makes each tick, so its time is above 0

return function (): (boolean, string | nil)
	local globals: any = Environment.load(GLOBALS)
	local frames: Frames.Frames = Frames.new(globals)
	local Tick: any = globals.require(globals.game:GetService("ReplicatedStorage").Packages.Tread.Server.Tick)

	Tick.start(RATE, CATCH_UP, {
		{
			name = "busy",
			run = function (_: number)
				local sum: number = 0
				for index: number = 1, WORK do
					sum += index
				end
			end,
		},
	})

	frames:run(1 / RATE)

	local stage: any = Tick.stages()[1]
	if stage.held ~= 1 or not (stage.last > 0) or stage.times[1] ~= stage.last then
		return false, `After a tick the stage holds {stage.held} times, its last {stage.last}`
	end

	for _ = 2, WINDOW + PAST do
		frames:run(1 / RATE)
	end

	if stage.held ~= WINDOW or #stage.times ~= WINDOW then
		return false, `After {WINDOW + PAST} ticks the stage holds {stage.held} of {#stage.times} times, not {WINDOW}`
	end

	for index: number = 1, WINDOW do
		if not (stage.times[index] > 0) then
			return false, `The stage's time {index} is {stage.times[index]}`
		end
	end

	return true, nil
end
