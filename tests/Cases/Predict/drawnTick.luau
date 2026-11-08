--[[
    Predict.drawn gives the u16 tick the body is drawn at, between its last
    two predicted ticks by the clock's fraction across the u16 wrap: nil
    before the first OwnerState and after a reset, and an error before start
--]]

--!strict
local Environment = require("../../Environment")
local Harness = require("../../Fixtures/Predict/Harness")

local PREDICT: string = "src/Client/Predict.luau"
local SPAWN_TICK: number = 65534 -- Two before the u16 wrap, so the ticks drawn cross it

-- Each frame's length in simulation ticks, quarters so every fraction is exact, and the tick drawn after it
local FRAMES: { { ticks: number, drawn: number } } = {
	{ ticks = 0.5, drawn = 65534 }, -- No tick yet, so the spawn's state is both of the last two
	{ ticks = 0.5, drawn = 65534 }, -- The first tick, at a fraction of 0
	{ ticks = 0.25, drawn = 65534.25 },
	{ ticks = 1, drawn = 65535.25 }, -- The next tick is the wrap's 0
	{ ticks = 0.5, drawn = 65535.75 },
	{ ticks = 0.5, drawn = 0.25 }, -- Half a tick on, past the wrap
}

return function (): (boolean, string | nil)
	-- Before start it errors, as every other Predict call does
	local unstarted: any = Environment.load(PREDICT)
	if pcall(unstarted.drawn) then
		return false, "Predict.drawn answered before Predict.start"
	end

	local rig: any = Harness.new()
	local Predict: any = rig.Predict
	if Predict.drawn() ~= nil then
		return false, `Predict.drawn gave {Predict.drawn()} before the first OwnerState`
	end

	rig.spawn(0, SPAWN_TICK)
	if Predict.drawn() ~= SPAWN_TICK then
		return false, `Predict.drawn gave {Predict.drawn()} at the spawn, not its tick {SPAWN_TICK}`
	end

	for index: number, frame: { ticks: number, drawn: number } in FRAMES do
		rig.frames(1, rig.delta * frame.ticks)

		local drawn: number? = Predict.drawn()
		if drawn ~= frame.drawn then
			return false, `After frame {index}, Predict.drawn gave {drawn}, where the body is drawn at {frame.drawn}`
		end
	end

	-- A reset ends the body, and with it the tick it is drawn at
	Predict.reset()
	if Predict.drawn() ~= nil then
		return false, `Predict.drawn gave {Predict.drawn()} after the body was reset`
	end

	return true, nil
end
