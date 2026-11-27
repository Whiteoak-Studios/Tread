--[[
    A sleeper seen once stays sent through sleepers.hold when a retest
    finds it blocked, is retested once the hold has passed with no walk of
    the viewer's, and hides then, the example's 2 s at 1.5 Hz
--]]

--!strict
local Environment = require("../../Environment")

local HARNESS: string = "tests/Fixtures/AntiEsp/Harness.luau"
local WALKED: vector = vector.create(5, 0, 0) -- Past the example's 4-stud retest

-- Each slice's time, whether it retests, and whether the sleeper is hidden after it
local STEPS: { { number | boolean } } = {
	{ 1, true, false }, -- Blocked inside the hold, so kept and retested at 2 s
	{ 1.5, false, false },
	{ 2, true, false }, -- At the hold's end, still inside it, so retested a rate's interval on
	{ 2.5, false, false },
	{ 2.7, true, true }, -- Past it
	{ 10, false, true },
}

return function (): (boolean, string | nil)
	local Harness: any = Environment.load(HARNESS)
	local harness: any = Harness.new()

	local slot: number, viewer: any = harness:player("Viewer", vector.zero)
	local sleeper: number = harness:body("Sleeper", vector.create(0, 0, -50))

	Harness.AntiEsp.isHidden(viewer, sleeper)
	harness:slice(0)
	if Harness.AntiEsp.isHidden(viewer, sleeper) then
		return false, "The sleeper with its rays open was hidden"
	end

	-- The viewer walks behind a wall, which makes the first retest due
	harness.wall = Harness.solid
	harness:move(slot, WALKED, viewer)

	for _, step: { number | boolean } in STEPS do
		local now: number = step[1] :: number
		local tested: boolean = step[2] :: boolean
		local hidden: boolean = step[3] :: boolean

		Harness.AntiEsp.isHidden(viewer, sleeper)
		harness:slice(now)

		if (#harness.rays > 0) ~= tested then
			return false, `At {now} s the sleeper pair cast {#harness.rays} rays, where a retest was {tested}`
		elseif Harness.AntiEsp.isHidden(viewer, sleeper) ~= hidden then
			return false, `After the slice at {now} s the sleeper was not {hidden and "hidden" or "visible"}`
		end
	end

	return true, nil
end
