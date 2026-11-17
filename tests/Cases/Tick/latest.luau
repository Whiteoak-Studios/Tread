--[[
    A stage given a latest runs at most once a Heartbeat, on the last of its
    ticks the latest takes, while every other stage runs on each; a hold on
    an earlier tick leaves it the release's last, and one it makes waits
--]]

--!strict
local Environment = require("../../Environment")
local Frames = require("../../Fixtures/Server/Frames")

local GLOBALS: string = "tests/Fixtures/Environment/Globals.luau"
local RATE: number = 20
local CATCH_UP: number = 2
local HALF: number = 0.5 -- A tick's share past the first frame's whole tick, so no later frame lands on a tick's edge
local STALL: number = 5 -- Whole ticks of time one frame owes, past the catch-up

return function (): (boolean, string | nil)
	local globals: any = Environment.load(GLOBALS)
	local frames: Frames.Frames = Frames.new(globals)
	local Tick: any = globals.require(globals.game:GetService("ReplicatedStorage").Packages.Tread.Server.Tick)

	local order: { string } = {}
	local runs: { [string]: number } = {}
	local holds: { [number]: string } = {} -- The stage that holds on each tick it names
	local evenOnly: boolean = false -- Whether the latest takes even ticks alone, as a relay slower than the simulation

	-- The stages run since the last call, which it clears
	local function taken(): string
		local got: string = table.concat(order, ", ")
		table.clear(order)

		return got
	end

	local function stage(name: string, latest: ((tick: number) -> boolean)?): { [string]: any }
		return {
			name = name,
			latest = latest,
			run = function (tick: number)
				table.insert(order, `{name} {tick}`)
				runs[name] = (runs[name] or 0) + 1

				if holds[tick] == name then
					Tick.hold()
				end
			end,
		}
	end

	local function latest(tick: number): boolean
		return not evenOnly or tick % 2 == 0
	end

	-- A latest that is no function is refused, naming it
	local bad: { [string]: any } = stage("bad", nil)
	bad.latest = true
	local started: boolean, message: any = pcall(Tick.start, RATE, CATCH_UP, { bad })
	if started or not string.find(tostring(message), "latest", 1, true) then
		return false, `A latest that is no function was not refused naming it: {message}`
	end

	Tick.start(
		RATE,
		CATCH_UP,
		{ stage("before", nil), stage("holder", nil), stage("last", latest), stage("after", nil) }
	)

	-- Each frame with what it runs: one tick, two, one, and one past the catch-up running two
	local steps: { { owed: number, ran: string } } = {
		{ owed = 1 + HALF, ran = "before 1, holder 1, last 1, after 1" },
		{ owed = CATCH_UP, ran = "before 2, holder 2, after 2, before 3, holder 3, last 3, after 3" },
		{ owed = 1, ran = "before 4, holder 4, last 4, after 4" },
		{ owed = STALL, ran = "before 5, holder 5, after 5, before 6, holder 6, last 6, after 6" },
	}

	for _, step: { owed: number, ran: string } in steps do
		frames:run(step.owed / RATE)

		local got: string = taken()
		if got ~= step.ran then
			return false, `A frame owing {step.owed} ticks ran {got}, not {step.ran}`
		end
	end

	-- A latest taking even ticks alone runs on none of an odd tick's frame, and on the first of two when the second is odd
	evenOnly = true
	frames:run(1 / RATE)
	local got: string = taken()
	if got ~= "before 7, holder 7, after 7" then
		return false, `A frame of one tick the latest refuses ran {got}`
	end

	frames:run(CATCH_UP / RATE)
	got = taken()
	if got ~= "before 8, holder 8, last 8, after 8, before 9, holder 9, after 9" then
		return false, `A frame whose last tick the latest refuses ran {got}`
	end

	-- A stage the latest skips never runs, so it can't hold there
	evenOnly = false
	holds[10] = "last"
	frames:run(CATCH_UP / RATE)
	got = taken()
	if got ~= "before 10, holder 10, after 10, before 11, holder 11, last 11, after 11" then
		return false, `A frame whose skipped stage would hold ran {got}`
	elseif pcall(Tick.release) then
		return false, "A stage the latest skipped held the tick"
	end

	-- A hold on the first of two ticks: its release skips the stage there and runs it on the tick after
	holds[12] = "holder"
	frames:run(CATCH_UP / RATE)
	got = taken()
	if got ~= "before 12, holder 12" then
		return false, `A frame whose first tick held ran {got}`
	end

	Tick.release()
	got = taken()
	if got ~= "after 12, before 13, holder 13, last 13, after 13" then
		return false, `The release of a hold on the first of two ticks ran {got}`
	end

	-- A hold the stage makes on the last tick: the release runs the ticks owed since, with the stage on the last alone
	holds[15] = "last"
	frames:run(CATCH_UP / RATE)
	got = taken()
	if got ~= "before 14, holder 14, after 14, before 15, holder 15, last 15" then
		return false, `A frame whose last tick's stage held ran {got}`
	end

	frames:run(CATCH_UP / RATE)
	got = taken()
	if got ~= "" then
		return false, `A held frame ran {got}`
	end

	Tick.release()
	got = taken()
	if got ~= "after 15, before 16, holder 16, after 16, before 17, holder 17, last 17, after 17" then
		return false, `The release of the stage's own hold ran {got}`
	end

	-- Each ring times its own stage's runs alone, so the skipped ticks leave the stage's times as they were
	for _, ring: any in Tick.stages() do
		if ring.held ~= runs[ring.name] then
			return false, `The {ring.name} stage ran {runs[ring.name]} times and its ring holds {ring.held}`
		end
	end

	return true, nil
end
