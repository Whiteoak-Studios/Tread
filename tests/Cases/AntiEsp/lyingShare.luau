--[[
    A slice with sleepers waiting and more player pairs due than it has time
    for tests sleepers first, starting none its mean test says would end
    past the lying share, then gives the rest of its budget to player pairs
--]]

--!strict
local Environment = require("../../Environment")

local HARNESS: string = "tests/Fixtures/AntiEsp/Harness.luau"
local SPIN: number = 0.002 -- Seconds of os.clock each slow ray takes; a test casts one, as its first ray is open
local SHARE: number = 2.5 * SPIN -- The lying share: two tests' mean ends inside it, a third's past it
local SHARE_TESTS: number = 2
local BUDGET: number = 8.5 * SPIN -- Room for a few player tests after the share, far short of every player's
local SLEEPERS: number = 4
local PLAYERS: number = 12
local SPACING: number = 10 -- Studs between neighbors, sleepers along -X and players along +X
local LATER: number = 0.05 -- Seconds on, at the starved slice

-- Holds the thread for SPIN seconds of os.clock, then lets the ray through
local function slow(_: vector, _: vector): boolean
	local stop: number = os.clock() + SPIN
	while os.clock() < stop do
		continue
	end

	return false
end

return function (): (boolean, string | nil)
	local Harness: any = Environment.load(HARNESS)
	local harness: any = Harness.new(function (_: any, server: any)
		server.antiEsp.lyingShare = SHARE
	end)
	local AntiEsp: any = Harness.AntiEsp
	harness.wall = Harness.solid

	local own: number, viewer: any = harness:player("Viewer", vector.zero)
	local targets: { number } = {}

	for index: number = 1, SLEEPERS do
		table.insert(targets, harness:body("Sleeper", vector.create(-SPACING * index, 0, 0)))
	end

	for index: number = 1, PLAYERS do
		table.insert(targets, harness:body("Player", vector.create(SPACING * index, 0, 0)))
	end

	local function ask()
		for _, target: number in targets do
			AntiEsp.isHidden(viewer, target)
		end
	end

	-- Every pair tested hidden, then all of them due at once by the viewer's own move, as a full load leaves them
	ask()
	harness:slice(0)
	ask()
	AntiEsp.lying()
	AntiEsp.moved(own)

	harness.wall = slow
	harness:slice(LATER, BUDGET)

	-- A ray's end along X tells a sleeper's test from a player's
	local lyingRays: number = 0
	local playerRays: number = 0
	for _, ray: any in harness.rays do
		if ray.to.x > 0 then
			playerRays += 1
		elseif playerRays > 0 then
			return false, "A sleeper pair was tested after a player pair, inside the sleepers' share"
		else
			lyingRays += 1
		end
	end

	local tests: number, waiting: number = AntiEsp.lying()
	if tests == 0 then
		return false, `With {SLEEPERS} sleepers waiting under {PLAYERS} due players, the slice tested no sleeper`
	elseif tests > SHARE_TESTS then
		return false, `The slice ran {tests} sleeper tests, past the {SHARE_TESTS} whose mean ends inside the share`
	elseif tests ~= lyingRays or waiting ~= SLEEPERS - tests then
		return false, `{tests} sleeper tests cast {lyingRays} rays and left {waiting} waiting`
	elseif playerRays == 0 or playerRays >= PLAYERS then
		return false, `After the sleepers' share the slice tested {playerRays} of {PLAYERS} due players`
	end

	return true, nil
end
