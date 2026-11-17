--[[
    Each stage's ring keeps the tick each of its times ran on, at the time's
    own index, so a latest stage a catch-up Heartbeat skips holds no tick for
    the one it skipped while a stage with none holds every tick
--]]

--!strict
local Environment = require("../../Environment")
local Frames = require("../../Fixtures/Server/Frames")

local GLOBALS: string = "tests/Fixtures/Environment/Globals.luau"
local RATE: number = 20
local CATCH_UP: number = 2
local HALF: number = 0.5 -- A tick's share past the first frame's whole tick, so no later frame lands on a tick's edge

-- Each frame's ticks owed: one, then two whose first the latest stage skips, then one
local OWED: { number } = { 1 + HALF, CATCH_UP, 1 }

-- The ticks each stage's ring holds after the frames, in the order its times went in
local EXPECTED: { [string]: string } = { every = "1,2,3,4", latest = "1,3,4" }

return function (): (boolean, string | nil)
	local globals: any = Environment.load(GLOBALS)
	local frames: Frames.Frames = Frames.new(globals)
	local Tick: any = globals.require(globals.game:GetService("ReplicatedStorage").Packages.Tread.Server.Tick)

	Tick.start(RATE, CATCH_UP, {
		{ name = "every", run = function (_: number) end },
		{
			name = "latest",
			run = function (_: number) end,
			latest = function (_: number): boolean
				return true
			end,
		},
	})

	for _, owed: number in OWED do
		frames:run(owed / RATE)
	end

	for _, stage: any in Tick.stages() do
		local ticks: string = table.concat(table.move(stage.ticks, 1, stage.held, 1, {}), ",")

		if #stage.ticks ~= #stage.times then
			return false, `The {stage.name} stage's ring keeps {#stage.ticks} ticks beside {#stage.times} times`
		elseif ticks ~= EXPECTED[stage.name] then
			return false, `The {stage.name} stage's ring holds the ticks {ticks}, not {EXPECTED[stage.name]}`
		end
	end

	return true, nil
end
