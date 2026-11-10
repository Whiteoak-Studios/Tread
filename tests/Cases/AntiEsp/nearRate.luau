--[[
    A hidden player pair whose target stands within antiEsp.nearRadius of the
    viewer's eye comes due again 1/30 s after its test, one 300 studs apart
    after the hidden rate's 1/10 s, and a visible pair after 1/2 s at both
--]]

--!strict
local Environment = require("../../Environment")

local HARNESS: string = "tests/Fixtures/AntiEsp/Harness.luau"
local NEAR: number = 200 -- Studs from the viewer, inside the example's 250-stud near radius
local FAR: number = 300
local EARLY: number = 0.9 -- The share of an interval at which a slice comes before the recheck is due

-- One pair's run: how far its target stands, whether every ray is blocked, and the interval its recheck keeps
type Trial = { distance: number, blocked: boolean, interval: (server: any) -> number }

local TRIALS: { Trial } = {
	{
		distance = NEAR,
		blocked = true,
		interval = function (server: any): number
			return 1 / server.antiEsp.nearRate
		end,
	},
	{
		distance = FAR,
		blocked = true,
		interval = function (server: any): number
			return 1 / server.antiEsp.hiddenRate
		end,
	},
	{
		distance = NEAR,
		blocked = false,
		interval = function (server: any): number
			return 1 / server.antiEsp.visibleRate
		end,
	},
	{
		distance = FAR,
		blocked = false,
		interval = function (server: any): number
			return 1 / server.antiEsp.visibleRate
		end,
	},
}

return function (): (boolean, string | nil)
	for _, trial: Trial in TRIALS do
		local Harness: any = Environment.load(HARNESS)
		local harness: any = Harness.new()
		if trial.blocked then
			harness.wall = Harness.solid
		end

		local _, viewer: any = harness:player("Viewer", vector.zero)
		local target: number = harness:body("Player", vector.create(0, 0, -trial.distance))
		Harness.AntiEsp.isHidden(viewer, target)

		-- The module's own sum, so each recheck lands on its slice's time to the bit
		local interval: number = trial.interval(harness.server)
		local slices: { { number | boolean } } = {
			{ 0, true },
			{ interval * EARLY, false },
			{ 0 + interval, true },
			{ interval + interval * EARLY, false },
			{ interval + interval, true },
		}

		local kind: string = trial.blocked and "hidden" or "visible"
		for _, slice: { number | boolean } in slices do
			local now: number = slice[1] :: number
			local tested: boolean = slice[2] :: boolean

			harness:slice(now)

			if (#harness.rays > 0) ~= tested then
				local due: string = tested and "" or "not "
				local cast: string = `A {kind} pair {trial.distance} studs apart cast {#harness.rays} rays at {now} s`
				return false, `{cast}, where a test was {due}due`
			elseif Harness.AntiEsp.isHidden(viewer, target) ~= trial.blocked then
				return false, `A pair {trial.distance} studs apart was not {kind} after the slice at {now} s`
			end
		end
	end

	return true, nil
end
