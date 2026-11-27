--[[
    A stage's hold stops the rest of its tick and every later one, between
    stages included, until the release runs them, keeping owed ticks up to
    the catch-up and dropping the rest, with one between pass a Heartbeat
--]]

--!strict
local Environment = require("../../Environment")
local Frames = require("../../Fixtures/Server/Frames")

local GLOBALS: string = "tests/Fixtures/Environment/Globals.luau"
local RATE: number = 20
local CATCH_UP: number = 2
local HALF: number = 0.5 -- A tick's share past a frame's whole ticks, so none lands on a tick's edge
local QUARTER: number = 0.25 -- A smaller share, which with a half left over still owes no tick
local STALL: number = 5 -- Whole ticks of time the held frames owe, past the catch-up

return function (): (boolean, string | nil)
	local globals: any = Environment.load(GLOBALS)
	local frames: Frames.Frames = Frames.new(globals)
	local Tick: any = globals.require(globals.game:GetService("ReplicatedStorage").Packages.Tread.Server.Tick)

	local order: { string } = {}
	local runs: { [string]: number } = {}
	local holds: { [number]: string } = {} -- How the holder holds on each tick it names: once, twice or releasing itself
	local secondHeld: boolean, secondMessage: any = true, nil

	-- Whether a call was refused with a message naming it
	local function refused(call: () -> (), name: string): boolean
		local ran: boolean, message: any = pcall(call)

		return not ran and string.find(tostring(message), name, 1, true) ~= nil
	end

	-- The stages run since the last call, which it clears, and the counts
	local function taken(): string
		local ran: number, dropped: number = Tick.counts()
		local got: string = `{table.concat(order, ", ")}; ran {ran}, dropped {dropped}`
		table.clear(order)

		return got
	end

	local function stage(name: string, between: boolean): { name: string, between: boolean, run: (tick: number) -> () }
		return {
			name = name,
			between = between,
			run = function (tick: number)
				table.insert(order, `{name} {tick}`)
				runs[name] = (runs[name] or 0) + 1

				local how: string? = holds[tick]
				if name ~= "holder" or how == nil then
					return
				end

				Tick.hold()
				if how == "twice" then
					secondHeld, secondMessage = pcall(Tick.hold)
				elseif how == "releasing" then
					Tick.release()
				end
			end,
		}
	end

	if not refused(Tick.hold, "Tick.hold") or not refused(Tick.release, "Tick.release") then
		return false, "A hold or a release before the tick started was not refused naming its call"
	end

	Tick.start(RATE, CATCH_UP, {
		stage("before", false),
		stage("slices", true),
		stage("holder", false),
		stage("after", false),
	})

	if not refused(Tick.hold, "Tick.hold") then
		return false, "A hold outside a running stage was not refused naming its call"
	end

	-- A catch-up frame whose first tick holds, released in the same frame: the rest run as later ticks
	holds[1] = "twice"
	frames:run((CATCH_UP + HALF) / RATE)

	local got: string = taken()
	if got ~= "before 1, slices 1, holder 1; ran 1, dropped 0" then
		return false, `A catch-up frame whose first tick held ran {got}`
	elseif secondHeld or not string.find(tostring(secondMessage), "Tick.hold", 1, true) then
		return false, `A second hold while held was not refused naming its call: {secondMessage}`
	end

	Tick.release()

	got = taken()
	if got ~= "after 1, before 2, holder 2, after 2; ran 2, dropped 0" then
		return false, `A release in the frame of its hold ran {got}`
	end

	-- Held Heartbeats run nothing, and the release keeps their ticks up to the catch-up and drops the rest
	holds[3] = "once"
	frames:run(1 / RATE)
	taken()
	frames:run(STALL / RATE)
	frames:run(QUARTER / RATE)

	got = taken()
	if got ~= "; ran 3, dropped 0" then
		return false, `Held Heartbeats ran {got}`
	elseif not refused(Tick.hold, "Tick.hold") then
		return false, "A hold from outside a stage while held was not refused naming its call"
	end

	Tick.release()

	got = taken()
	if got ~= "after 3, before 4, slices 4, holder 4, after 4, before 5, holder 5, after 5; ran 5, dropped 3" then
		return false, `A release after held Heartbeats owing {STALL} ticks ran {got}`
	end

	-- After a held Heartbeat owing no tick, a release runs its between pass, and in the hold's own frame it doesn't
	holds[6] = "once"
	frames:run(HALF / RATE)
	taken()
	frames:run(HALF / RATE)
	Tick.release()

	got = taken()
	if got ~= "after 6, slices 6; ran 6, dropped 3" then
		return false, `A release after a held Heartbeat owing no tick ran {got}`
	end

	holds[7] = "once"
	frames:run(HALF / RATE)
	taken()
	Tick.release()

	got = taken()
	if got ~= "after 7; ran 7, dropped 3" then
		return false, `A release in its hold's frame owing no tick ran {got}`
	end

	frames:run(QUARTER / RATE)

	got = taken()
	if got ~= "slices 7; ran 7, dropped 3" then
		return false, `A frame owing no tick after a release ran {got}`
	end

	-- A tick a release runs may hold again, keeping the rest owed for the next release
	holds[8] = "once"
	holds[9] = "once"
	frames:run((CATCH_UP + QUARTER) / RATE)
	taken()
	Tick.release()

	got = taken()
	if got ~= "after 8, before 9, holder 9; ran 9, dropped 3" then
		return false, `A release whose next tick held again ran {got}`
	end

	Tick.release()

	got = taken()
	if got ~= "after 9; ran 9, dropped 3" then
		return false, `The second release ran {got}`
	end

	-- A release before the holding stage returns lets its tick go straight on
	holds[10] = "releasing"
	frames:run(HALF / RATE)

	got = taken()
	if got ~= "before 10, slices 10, holder 10, after 10; ran 10, dropped 3" then
		return false, `A stage that released its own hold ran its tick as {got}`
	elseif not refused(Tick.release, "Tick.release") then
		return false, "A release with nothing held was not refused naming its call"
	end

	-- Each stage's ring times its own runs alone, the holder's run before the release included
	for _, ring: any in Tick.stages() do
		if ring.held ~= runs[ring.name] then
			return false, `The {ring.name} stage ran {runs[ring.name]} times and its ring holds {ring.held}`
		end
	end

	return true, nil
end
