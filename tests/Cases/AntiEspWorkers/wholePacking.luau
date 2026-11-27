--[[
    Running whole with a worker, a slice that begins at its tests packs its
    due pairs for the worker and is then cut in its drains, and still sends
    the batch, which lands and settles at the next slice, while the cut
    drain's entry waits for the drains to come round again
--]]

--!strict
local Environment = require("../../Environment")
local StandIn = require("../../Fixtures/AntiEspWorkers/Pool")

local HARNESS: string = "tests/Fixtures/AntiEsp/Harness.luau"
local POOL: string = "ReplicatedStorage.Packages.Tread.Server.RelayWorkers.Pool"
local WORKERS: number = 1
local STEP: number = 1 / 64 -- Seconds from one slice to the next
local DUE: number = 0.5 -- When the visible player's 2 Hz recheck and both hidden 10 Hz ones are due
local WALLED: { number } = { -300, -310 } -- Each hidden player's Z, past the example's 250-stud near radius
local SEEN: vector = vector.create(20, 0, 0)
local HIDDEN_RAYS: number = 6

-- The cut slices' late reads: the deadline, the hidden queue's first entry, then the visible queue's, found passed;
-- then, begun at the tests, the deadline, their start, before and after each hidden pair packed, then the visible
-- queue's entry, found passed
local DRAINS_CUT: number = 3
local PACKED_CUT: number = 7

return function (): (boolean, string | nil)
	local override: { [string]: any } = StandIn.override()
	local Harness: any = Environment.load(HARNESS, { [POOL] = override })
	local clock: any = Harness.clock()
	local harness: any = Harness.new(function (_: any, server: any)
		server.antiEsp.workers = WORKERS
	end, clock.read)

	local AntiEsp: any = Harness.AntiEsp
	local pool: any = override.made
	AntiEsp.useWhole(true)

	local walled: { [number]: boolean } = {}
	for _, z: number in WALLED do
		walled[z] = true
	end

	local function wall(origin: vector, direction: vector): boolean
		return walled[math.round((origin + direction).z)] == true
	end

	harness.wall = wall
	pool.wall = wall

	local _, viewer: any = harness:player("Viewer", vector.zero)
	local targets: { number } = {}
	for _, z: number in WALLED do
		table.insert(targets, harness:body("Player", vector.create(0, 0, z)))
	end
	local seen: number = harness:body("Player", SEEN)

	local function ask()
		for _, slot: number in targets do
			AntiEsp.isHidden(viewer, slot)
		end

		AntiEsp.isHidden(viewer, seen)
	end

	-- All three packed at 0 s and landed at the next slice, the hidden two on the 10 Hz queue and the seen one on the
	-- 2 Hz one, then asked about once more, with no ask between the slices after
	ask()
	harness:slice(0)
	harness:slice(STEP)
	ask()

	if #pool.sends ~= 1 or AntiEsp.counts() ~= 3 then
		return false, `The first batch wasn't sent and landed, {#pool.sends} sent and {AntiEsp.counts()} settled`
	end

	-- Cut in its drains, with both hidden rechecks taken and the visible one left: nothing packed, nothing sent
	table.clear(pool.rays)
	harness:sliceOn(clock, DUE, DRAINS_CUT)

	if #pool.sends ~= 1 or #pool.rays ~= 0 or #harness.rays ~= 0 then
		return false, `The slice cut in its drains sent {#pool.sends - 1} batches`
	end

	-- Begun at its tests, which pack both hidden pairs, then cut at the visible queue's entry: the batch still goes
	harness:sliceOn(clock, DUE + STEP, PACKED_CUT)

	local sent: any = pool.sends[2]
	if sent == nil or sent.pairs ~= #targets then
		return false, "The slice cut after packing its tests sent no batch of both hidden pairs"
	elseif #pool.rays ~= HIDDEN_RAYS * #targets or #harness.rays ~= 0 then
		return false, `The worker cast {#pool.rays} rays and the main thread {#harness.rays}, not the hidden pairs'`
	elseif AntiEsp.cuts() ~= 2 then
		return false, `The two cut slices counted {AntiEsp.cuts()} cuts`
	end

	-- The next slice lands both and settles them hidden, and packs the visible one its drains now reach
	local tests: number, hidden: number = AntiEsp.counts()
	harness:sliceOn(clock, DUE + 2 * STEP)

	local nowTests: number, nowHidden: number = AntiEsp.counts()
	if nowTests - tests ~= #targets or nowHidden - hidden ~= #targets then
		return false, `The packed batch landed {nowTests - tests} tests, {nowHidden - hidden} hidden, not both hidden`
	elseif pool.sends[3] == nil or pool.sends[3].pairs ~= 1 then
		return false, "The visible pair the cut left waiting wasn't packed once the drains came round"
	end

	for _, slot: number in targets do
		if AntiEsp.reason(viewer.key, slot) ~= "Hidden" then
			return false, `A packed hidden pair read {AntiEsp.reason(viewer.key, slot)} once its batch landed`
		end
	end

	return true, nil
end
