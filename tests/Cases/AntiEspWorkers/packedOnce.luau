--[[
    A held sleeper pair that a walk sends to a worker is packed once at the
    next slice, which gives that batch up as not back, though its hold's
    retest timer comes due there too, so one test is cast for it, not two
--]]

--!strict
local Environment = require("../../Environment")
local StandIn = require("../../Fixtures/AntiEspWorkers/Pool")

local HARNESS: string = "tests/Fixtures/AntiEsp/Harness.luau"
local POOL: string = "ReplicatedStorage.Packages.Tread.Server.RelayWorkers.Pool"
local WORKERS: number = 2
local WALK: vector = vector.create(10, 0, 0) -- Studs a walk moves the viewer, past the example's 4-stud retest
local SLEEPER: vector = vector.create(0, 0, -50)

-- When each slice runs, and what happens around it
local LANDS: number = 0.02 -- The first test's batch comes back, the sleeper seen
local HELD_WALK: number = 0.7 -- A walk with the rate allowing sends it again, every ray now blocked, so it is held
local LANDS_HELD: number = 0.72 -- That answer back: held visible, its retest timer at the hold's end, 2 s after seen
local SENT_WALK: number = 1.5 -- A second walk with the rate allowing sends it again, and the case keeps that batch
local TIMER: number = 2.1 -- The next slice, past the hold's timer, which finds the batch kept out not back

return function (): (boolean, string | nil)
	local override: { [string]: any } = StandIn.override()
	local Harness: any = Environment.load(HARNESS, { [POOL] = override })
	local harness: any = Harness.new(function (_: any, server: any)
		server.antiEsp.workers = WORKERS
	end)

	local AntiEsp: any = Harness.AntiEsp
	local pool: any = override.made
	local own: number, viewer: any = harness:player("Viewer", vector.zero)
	local sleeper: number = harness:body("Sleeper", SLEEPER)
	local hold: number = harness.server.sleepers.hold

	if TIMER <= hold then
		return false, "The case's times no longer put the hold's timer before the slice after the kept batch's"
	end

	-- Seen open at its first test
	AntiEsp.isHidden(viewer, sleeper)
	harness:slice(0)
	harness:slice(LANDS)

	if AntiEsp.reason(viewer.key, sleeper) ~= "Clear" then
		return false, "The open sleeper was not seen by its first test"
	end

	-- Held visible by a blocked retest after a walk
	pool.wall = Harness.solid
	harness:move(own, WALK, viewer)
	table.clear(pool.sends)
	harness:slice(HELD_WALK)
	harness:slice(LANDS_HELD)

	if #pool.sends ~= 1 or AntiEsp.reason(viewer.key, sleeper) ~= "Hold" then
		return false, "The walk's blocked retest did not leave the sleeper held visible"
	end

	-- Sent again by a second walk, that batch kept out
	harness:move(own, WALK * 2, viewer)
	table.clear(pool.sends)
	harness:slice(SENT_WALK)

	if #pool.sends ~= 1 then
		return false, "The second walk did not send the sleeper's pair again"
	end

	pool.held[pool.sends[1].worker] = true
	table.clear(pool.sends)

	-- The next slice gives the batch up and packs the pair again for the other worker, and its hold's timer, due
	-- there too, packs nothing more, as the pair was restamped when it went out
	harness:slice(TIMER)

	if #pool.sends ~= 1 or pool.sends[1].pairs ~= 1 or #harness.rays ~= 0 then
		return false, "The sleeper's pair given up was not packed once when its hold's timer came due"
	end

	return true, nil
end
