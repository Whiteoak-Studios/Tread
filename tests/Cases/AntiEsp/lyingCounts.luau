--[[
    AntiEsp.lying gives the sleepers' and bodies' pair tests since its last
    call and their pairs waiting due: a slice with no time tests none and
    leaves them waiting, a pair due again counted once, and one with time
    tests them and leaves none, a player pair's test never among them
--]]

--!strict
local Environment = require("../../Environment")

local HARNESS: string = "tests/Fixtures/AntiEsp/Harness.luau"
local LYING: number = 2 -- The sleeper's pair and the body's

return function (): (boolean, string | nil)
	local Harness: any = Environment.load(HARNESS)
	local harness: any = Harness.new()
	local AntiEsp: any = Harness.AntiEsp

	local _, viewer: any = harness:player("Viewer", vector.zero)
	local player: number = harness:body("Player", vector.create(0, 0, -50))
	local sleeper: number = harness:body("Sleeper", vector.create(50, 0, 0))
	local body: number = harness:body("Body", vector.create(-50, 0, 0))

	AntiEsp.isHidden(viewer, player)
	AntiEsp.isHidden(viewer, sleeper)
	AntiEsp.isHidden(viewer, body)

	-- No time: every pair waits untested, the player's in a heap of its own
	harness:slice(0, 0)

	local tests: number, waiting: number = AntiEsp.lying()
	local all: number = AntiEsp.counts()
	if tests ~= 0 or waiting ~= LYING or all ~= 0 then
		local counts: string = `{tests} lying tests of {all} and {waiting} waiting`
		return false, `A slice with no time gave {counts}, not 0 of 0 and {LYING}`
	end

	-- A waiting pair made due again waits once, its older entry stale
	AntiEsp.moved(sleeper)
	harness:slice(0.1, 0)

	tests, waiting = AntiEsp.lying()
	if tests ~= 0 or waiting ~= LYING then
		return false, `With the sleeper due again, a slice with no time gave {tests} tests and {waiting} waiting`
	end

	-- Time for every test: both lying pairs are tested and none waits, the player pair's test not counted
	harness:slice(0.2)

	tests, waiting = AntiEsp.lying()
	all = AntiEsp.counts()
	if tests ~= LYING or waiting ~= 0 then
		return false, `A slice with time gave {tests} lying tests and {waiting} waiting, not {LYING} and 0`
	elseif all ~= LYING + 1 then
		return false, `The slice ran {all} tests in all, not the {LYING} lying pairs' and the player pair's`
	end

	-- The tests are counted from the last call
	tests, waiting = AntiEsp.lying()
	if tests ~= 0 or waiting ~= 0 then
		return false, `A call straight after another gave {tests} lying tests and {waiting} waiting`
	end

	return true, nil
end
