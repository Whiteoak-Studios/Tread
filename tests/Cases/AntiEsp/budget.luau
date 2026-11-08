--[[
    A slice stops once its budget has passed, and works through what is due
    in order: overdue hidden player pairs nearest first, then visible ones,
    then sleepers, one test a slice where each test outlasts the budget
--]]

--!strict
local Environment = require("../../Environment")

local HARNESS: string = "tests/Fixtures/AntiEsp/Harness.luau"
local SPIN: number = 0.002 -- Seconds of os.clock each slow ray takes, so one test outlasts the budget
local BUDGET: number = 0.001
local LATER: number = 2 -- Seconds on, when every pair is due again
local FAR: number = 50 -- The setup slice opens a ray reaching this far along X, so one pair alone is seen
local REACH: number = 4 -- Studs across the ground from a target's feet that every ray to it ends within

-- Holds the thread for SPIN seconds of os.clock, then blocks the ray
local function slow(_: vector, _: vector): boolean
	local stop: number = os.clock() + SPIN
	while os.clock() < stop do
		continue
	end

	return true
end

return function (): (boolean, string | nil)
	local Harness: any = Environment.load(HARNESS)
	local harness: any = Harness.new()
	local AntiEsp: any = Harness.AntiEsp

	local _, viewer: any = harness:player("Viewer", vector.zero)

	local far: number = harness:body("Player", vector.create(0, 0, -30))
	local near: number = harness:body("Player", vector.create(0, 0, -10))
	local middle: number = harness:body("Player", vector.create(0, 0, -20))
	local seen: number = harness:body("Player", vector.create(100, 0, -5))
	local sleeper: number = harness:body("Sleeper", vector.create(-100, 0, 0))
	local order: { { any } } = {
		{ "the nearest hidden player", near },
		{ "the middle hidden player", middle },
		{ "the farthest hidden player", far },
		{ "the visible player", seen },
		{ "the sleeper", sleeper },
	}

	-- Asked about in the reverse of the order a slice takes them in, so the pairs' own order is no help
	for index: number = #order, 1, -1 do
		AntiEsp.isHidden(viewer, order[index][2])
	end

	harness.wall = function (_: vector, direction: vector): boolean
		return direction.x < FAR
	end
	harness:slice(0)

	-- The relay's next run asks about every pair, so none is dropped
	for _, entry: { any } in order do
		if AntiEsp.isHidden(viewer, entry[2]) ~= (entry[2] ~= seen) then
			return false, `The setup slice left {entry[1]} on the wrong side of its walls`
		end
	end

	-- Every pair due, the sleeper's by its move, and each ray slow
	AntiEsp.moved(sleeper)
	harness.wall = slow

	for index: number, entry: { any } in order do
		harness:slice(LATER, BUDGET)

		local feet: vector = harness.states[entry[2]].position
		local ends: number = 0
		for _, ray: any in harness.rays do
			local offset: vector = ray.to - feet
			if math.sqrt(offset.x * offset.x + offset.z * offset.z) < REACH then
				ends += 1
			end
		end

		if ends == 0 or ends ~= #harness.rays then
			return false, `Slice {index} cast {#harness.rays} rays, {ends} of them at {entry[1]}, whose turn it was`
		end
	end

	harness:slice(LATER, BUDGET)
	if #harness.rays ~= 0 then
		return false, `With every due pair tested, a slice still cast {#harness.rays} rays`
	end

	return true, nil
end
