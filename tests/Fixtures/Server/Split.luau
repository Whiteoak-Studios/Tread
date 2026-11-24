--[[
    A tick loop for the split's cases: a stage before, a between slice, a
    stage with an early part whose run holds with a poll and runs once a
    Heartbeat at most, and a stage after, with calm Heartbeats to drive it
--]]

--!strict
local Split = {}

local Environment = require("../../Environment")
local Frames = require("./Frames")

local GLOBALS: string = "tests/Fixtures/Environment/Globals.luau"
local RATE: number = 20
local CATCH_UP: number = 2
local START: number = 0.25 -- The first Heartbeat's share of a tick, so no later one lands on a tick's edge

-- A calm tick's three Heartbeats' shares of a tick, the tick beginning in the last, three after the tick before
local CALM: { number } = { 0.25, 0.25, 0.5 }

export type Loop = {
	Tick: any,
	frames: Frames.Frames,
	-- Each run as it came: "before", "slices", "early", "split", "after", "poll" for the split stage's poll and
	-- "poll <stage>" for another's, then the tick it was for
	order: { string },
	reports: { string }, -- Each report as "<kind> <measurement>"
	warns: { string }, -- Each warning the tick loop gave
	holds: boolean, -- Whether the split stage's run holds the tick with a poll, true from start
	answer: boolean, -- What that poll answers, true from start
	latest: (tick: number) -> boolean, -- The split stage's latest, true for every tick from start
	-- By a run's mark as it goes into order: "throws"; "holds", the tick held with a poll that answers true, or what
	-- Tick.hold threw kept as refusal; and for the split stage's run "releases", a hold it ends itself
	faults: { [string]: string },
	refusal: string?, -- What Tick.hold threw at the newest run that tried to hold and was refused
	spins: { early: number, split: number }, -- Seconds the early part and the split stage's run each hold the loop
}

-- Holds the loop for seconds
local function spin(seconds: number)
	local ends: number = os.clock() + seconds
	while os.clock() < ends do
		continue
	end
end

--[[
    A loop started at 20 ticks a second with a catch-up of 2, its split
    off, after one Heartbeat of a quarter of a tick, with nothing kept. The
    loop's warnings are kept in place of printed, through its environment
--]]

function Split.new(): Loop
	local globals: any = Environment.load(GLOBALS)
	local frames: Frames.Frames = Frames.new(globals)
	local tread: any = globals.game:GetService("ReplicatedStorage").Packages.Tread
	local Reports: any = globals.require(tread.Server.Reports)
	local Tick: any = globals.require(tread.Server.Tick)

	local loop: Loop = {
		Tick = Tick,
		frames = frames,
		order = {},
		reports = {},
		warns = {},
		holds = true,
		answer = true,
		latest = function (_: number): boolean
			return true
		end,
		faults = {},
		refusal = nil,
		spins = { early = 0, split = 0 },
	}

	-- The tick loop's own environment, the one table the test environment gave it, holds the warn it calls
	local scope: any = getfenv(Tick.start)
	scope.warn = function (text: string)
		table.insert(loop.warns, text)
	end

	Reports.connect(function (_: any, kind: string, measurement: any)
		table.insert(loop.reports, `{kind} {measurement}`)
	end)

	-- Does what the case set for a run by its mark, a throw or a hold, keeping what Tick.hold threw if it refused
	local function fault(at: string, name: string, tick: number)
		local kind: string? = loop.faults[at]
		if kind == "throws" then
			error(`The {name} stage throws on purpose at tick {tick}`)
		elseif kind ~= "holds" then
			return
		end

		local held: boolean, message: any = pcall(Tick.hold, function (): boolean
			table.insert(loop.order, `poll {name} {tick}`)

			return true
		end)

		if not held then
			loop.refusal = tostring(message)
		end
	end

	local function mark(name: string): (tick: number) -> ()
		return function (tick: number)
			local at: string = `{name} {tick}`
			table.insert(loop.order, at)
			fault(at, name, tick)
		end
	end

	Tick.start(RATE, CATCH_UP, {
		{ name = "before", run = mark("before") },
		{ name = "slices", between = true, run = mark("slices") },
		{
			name = "split",
			latest = function (tick: number): boolean
				return loop.latest(tick)
			end,
			early = function (tick: number)
				local at: string = `early {tick}`
				table.insert(loop.order, at)
				spin(loop.spins.early)
				fault(at, "early", tick)
			end,
			run = function (tick: number)
				local at: string = `split {tick}`
				table.insert(loop.order, at)
				spin(loop.spins.split)

				local kind: string? = loop.faults[at]
				if kind == "throws" then
					error("This stage throws on purpose, before it holds")
				elseif kind ~= "releases" and not loop.holds then
					return
				end

				Tick.hold(function (): boolean
					table.insert(loop.order, `poll {tick}`)

					return loop.answer
				end)

				if kind == "releases" then
					Tick.release()
				end
			end,
		},
		{ name = "after", run = mark("after") },
	})

	frames:run(START / RATE)
	table.clear(loop.order)

	return loop
end

-- Runs one Heartbeat of a share of a tick, giving the runs it made in order, which it clears
function Split.beat(loop: Loop, share: number): string
	loop.frames:run(share / RATE)

	local got: string = table.concat(loop.order, ", ")
	table.clear(loop.order)

	return got
end

-- Runs count calm ticks, each three Heartbeats after the tick before, giving every run they made in order
function Split.calm(loop: Loop, count: number): string
	local got: { string } = {}

	for _ = 1, count do
		for _, share: number in CALM do
			local ran: string = Split.beat(loop, share)
			if ran ~= "" then
				table.insert(got, ran)
			end
		end
	end

	return table.concat(got, ", ")
end

-- The newest Heartbeat's flags, as a sum of Tick's
function Split.flags(loop: Loop): number
	local beats: any = loop.Tick.heartbeats()

	return beats.flags[(beats.head - 1) % #beats.flags + 1]
end

-- The split stage as the loop keeps it, its ring included
function Split.stage(loop: Loop): any
	for _, stage: any in loop.Tick.stages() do
		if stage.name == "split" then
			return stage
		end
	end

	error("The loop has no split stage")
end

return Split
