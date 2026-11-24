--[[
    A result that lands after its pair moved, its viewer left and came
    back, its target was reborn or it failed open while in flight changes
    nothing, and the pair is tested again in the same slice
--]]

--!strict
local Environment = require("../../Environment")
local StandIn = require("../../Fixtures/AntiEspWorkers/Pool")

local HARNESS: string = "tests/Fixtures/AntiEsp/Harness.luau"
local POOL: string = "ReplicatedStorage.Packages.Tread.Server.RelayWorkers.Pool"
local WORKERS: number = 2
local STEP: number = 1 / 64
local SLICES: number = 40 -- The most slices any wait below runs before it fails
local FIRST: number = 1 -- The worker every lone pair goes to while it is idle

type Event = {
	name: string,
	stale: boolean, -- Whether the in-flight test meets the wall, the opposite of what the pair shows after the event
	hidden: boolean, -- Whether the pair is hidden after the event, which the stale result must not change
	run: (harness: any, AntiEsp: any, viewer: any, target: number, slice: (stall: number?) -> ()) -> boolean,
}

local EVENTS: { Event } = {
	{
		name = "moved",
		stale = false,
		hidden = true,
		run = function (_: any, AntiEsp: any, _: any, target: number, _: (stall: number?) -> ()): boolean
			AntiEsp.moved(target)

			return true
		end,
	},
	{
		name = "left",
		stale = false,
		hidden = true,
		run = function (_: any, AntiEsp: any, viewer: any, target: number, _: (stall: number?) -> ()): boolean
			AntiEsp.leave(viewer.key)
			AntiEsp.isHidden(viewer, target)

			return true
		end,
	},
	{
		name = "reborn",
		stale = false,
		hidden = true,
		run = function (harness: any, AntiEsp: any, viewer: any, target: number, _: (stall: number?) -> ()): boolean
			harness:reborn(target)
			AntiEsp.isHidden(viewer, target)

			return true
		end,
	},
	{
		name = "failed open",
		stale = true,
		hidden = false,
		run = function (harness: any, AntiEsp: any, viewer: any, target: number, slice: (stall: number?) -> ()): boolean
			-- The next slice comes after a stall, which gives the held batch up and sends its pair to the other
			-- worker, so the ask after it finds the pair untested past the fail-open time
			slice(harness.server.antiEsp.failOpen)

			return not AntiEsp.isHidden(viewer, target)
		end,
	},
}

local function check(event: Event): string?
	local override: { [string]: any } = StandIn.override()
	local Harness: any = Environment.load(HARNESS, { [POOL] = override })
	local harness: any = Harness.new(function (_: any, server: any)
		server.antiEsp.workers = WORKERS
	end)

	local AntiEsp: any = Harness.AntiEsp
	local pool: any = override.made
	local _, viewer: any = harness:player("Viewer", vector.zero)
	local target: number = harness:body("Player", vector.create(0, 0, -50))
	local now: number = 0

	-- One slice a step after the last, or after a stall that much longer
	local function slice(stall: number?)
		now += stall or 0
		harness:slice(now)
		now += STEP
	end

	-- Hidden from its first test, then sent again while the case holds its worker
	pool.wall = Harness.solid
	AntiEsp.isHidden(viewer, target)
	slice()
	slice()

	if not AntiEsp.isHidden(viewer, target) then
		return "the pair behind the wall was not hidden after its first test"
	end

	pool.wall = event.stale and Harness.solid or Harness.open
	pool.held[FIRST] = true
	table.clear(pool.sends)

	for _ = 1, SLICES do
		slice()
		AntiEsp.isHidden(viewer, target)

		if #pool.sends > 0 then
			break
		end
	end

	if #pool.sends ~= 1 or pool.sends[1].worker ~= FIRST then
		return "the pair's recheck was not sent to the first worker"
	elseif not event.run(harness, AntiEsp, viewer, target, slice) then
		return "the event never happened"
	elseif AntiEsp.isHidden(viewer, target) ~= event.hidden then
		return `the pair was not {event.hidden and "hidden" or "shown"} after the event`
	end

	local tests: number = AntiEsp.counts()
	pool.held[FIRST] = false
	table.clear(pool.rays)
	slice()

	local after: number = AntiEsp.counts()
	if after ~= tests then
		return `the stale result settled a test, {tests} becoming {after}`
	elseif AntiEsp.isHidden(viewer, target) ~= event.hidden then
		return "the stale result changed the pair's verdict"
	elseif #pool.rays == 0 then
		return "the pair was not tested again in the slice its stale result landed"
	end

	slice()
	if AntiEsp.counts() ~= tests + 1 then
		return "the pair's fresh test did not settle at the next slice"
	end

	return nil
end

return function (): (boolean, string | nil)
	for _, event: Event in EVENTS do
		local problem: string? = check(event)
		if problem then
			return false, `With the pair {event.name} in flight, {problem}`
		end
	end

	return true, nil
end
