--[[
    A stage marked between also runs on each Heartbeat that owes no tick,
    handed the newest tick run and timed into its ring, while the others
    wait for a tick; a between that is no boolean is refused
--]]

--!strict
local Environment = require("../../Environment")
local Frames = require("../../Fixtures/Server/Frames")

local GLOBALS: string = "tests/Fixtures/Environment/Globals.luau"
local RATE: number = 20
local CATCH_UP: number = 2
local SHORT: number = 0.4 -- A tick's share one short frame owes, so two of them owe none and a third passes one

return function (): (boolean, string | nil)
	local globals: any = Environment.load(GLOBALS)
	local frames: Frames.Frames = Frames.new(globals)
	local Tick: any = globals.require(globals.game:GetService("ReplicatedStorage").Packages.Tread.Server.Tick)

	if pcall(Tick.start, RATE, CATCH_UP, { { name = "odd", between = "yes", run = function (_: number) end } }) then
		return false, "Tick.start took a between that is a string"
	end

	local sliced: { number } = {}
	local ticked: { number } = {}

	Tick.start(RATE, CATCH_UP, {
		{
			name = "slices",
			between = true,
			run = function (tick: number)
				table.insert(sliced, tick)
			end,
		},
		{
			name = "ticks",
			run = function (tick: number)
				table.insert(ticked, tick)
			end,
		},
	})

	frames:run(SHORT / RATE)
	frames:run(SHORT / RATE)

	local slices: any = Tick.stages()[1]
	if #sliced ~= 2 or #ticked ~= 0 or sliced[1] ~= 0 or sliced[2] ~= 0 then
		return false, `Two frames owing no tick ran the between stage {#sliced} times and the other {#ticked}`
	elseif slices.held ~= 2 or slices.last ~= slices.times[2] then
		return false, `The between stage's ring holds {slices.held} times after two slices, not 2`
	end

	-- The third passes a whole tick, which runs every stage once, the between one inside the tick
	frames:run(SHORT / RATE)

	local ran: number = Tick.counts()
	if ran ~= 1 or #ticked ~= 1 or #sliced ~= 3 or sliced[3] ~= 1 or ticked[1] ~= 1 then
		return false, `The frame passing a tick ran {#ticked} ticks and {#sliced - 2} more slices, tick {ran}`
	end

	frames:run(SHORT / RATE)
	if #sliced ~= 4 or sliced[4] ~= 1 or #ticked ~= 1 then
		return false, "A frame owing no tick after one was not handed that tick's number"
	end

	return true, nil
end
