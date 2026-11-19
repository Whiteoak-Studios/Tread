--[[
    The rewind's terms and its cap: the queue wait counts at most its cap,
    the delay is clamped, a rewind never reaches past min(RTT, its cap)
    plus the wait, the delay and the extra ticks, nor past the ceiling, and
    the result stays inside the history and no later than its newest sample
--]]

--!strict
local Environment = require("../../Environment")

local HISTORY: string = "src/Server/History.luau"
local STATE: string = "src/Step/State.luau"
local EXAMPLE: string = "tests/Fixtures/Config/Example.luau"
local SLOT: number = 0
local TICK: number = 100 -- The command's tick, a relay tick too at the example's 20 and 20 Hz
local FAR: number = 0 -- A claim far outside any band, so each read gives the expected time as clamped
local NEAR: number = 1e-9

type Row = { name: string, rtt: number, wait: number, delay: number, want: number }

-- Writes the slot at every tick from first to last
local function write(History: any, State: any, first: number, last: number)
	local state = State.new()

	for at: number = first, last do
		History.write(SLOT, at, state, 0)
	end
end

-- Why any row rewinds apart from its due time, or nil when each matches
local function check(History: any, rows: { Row }, claimed: number?): string?
	for _, row: Row in rows do
		local time: number = History.rewindFor(TICK, row.rtt, 0, row.wait, row.delay, claimed or FAR)
		if math.abs(time - row.want) > NEAR then
			return `A shot {row.name} rewound to {time}, not {row.want}`
		end
	end

	return nil
end

return function (): (boolean, string | nil)
	local Example: any = Environment.load(EXAMPLE)
	local State: any = Environment.load(STATE)

	local History: any = Environment.load(HISTORY)
	History.start(Example.shared(), Example.server())
	write(History, State, TICK - 20, TICK - 1)

	local failure: string? = check(History, {
		{ name = "on a good connection", rtt = 0.1, wait = 1, delay = 0.15, want = 94 },
		{ name = "with no queue wait", rtt = 0, wait = 0, delay = 0.15, want = 97 },
		{ name = "with the queue wait at its cap", rtt = 0, wait = 3, delay = 0.15, want = 94 },
		{ name = "with the queue wait past its cap", rtt = 0, wait = 7, delay = 0.15, want = 94 },
		{ name = "with the delay below its floor", rtt = 0, wait = 0, delay = 0, want = 97 },
		{ name = "with the delay inside its range", rtt = 0, wait = 0, delay = 0.2, want = 96 },
		{ name = "with the delay above its top", rtt = 0, wait = 0, delay = 1, want = 95 },
		{
			name = "past the RTT cap, held to min(RTT, cap) + delay + extra",
			rtt = 0.4,
			wait = 0,
			delay = 0.15,
			want = 91,
		},
		{ name = "past the ceiling", rtt = 0.2, wait = 3, delay = 0.25, want = 90 },
		{ name = "with a long ping and everything at its top", rtt = 1, wait = 3, delay = 0.25, want = 90 },
	})

	if failure then
		return false, failure
	end

	-- With no extra ticks the RTT-capped reach shrinks by them
	local NoExtra: any = Environment.load(HISTORY)
	local bare = Example.server()
	bare.rewind.extra = 0
	NoExtra.start(Example.shared(), bare)
	write(NoExtra, State, TICK - 20, TICK - 1)

	failure = check(NoExtra, {
		{ name = "past the RTT cap with no extra ticks", rtt = 0.4, wait = 0, delay = 0.15, want = 93 },
	})

	if failure then
		return false, failure
	end

	-- A history whose newest sample is tick 95: a claim inside the band at 97.5 stays no later than it
	local Stale: any = Environment.load(HISTORY)
	Stale.start(Example.shared(), Example.server())
	write(Stale, State, 80, 95)

	failure = check(Stale, {
		{ name = "claimed past the newest sample", rtt = 0, wait = 0, delay = 0.15, want = 95 },
	}, 97.5)

	if failure then
		return false, failure
	end

	-- A quarter second of history holds 5 ticks back from the newest, 94, above the ceiling's 90
	local Short: any = Environment.load(HISTORY)
	local short = Example.server()
	short.history.seconds = 0.25
	Short.start(Example.shared(), short)
	write(Short, State, TICK - 20, TICK - 1)

	failure = check(Short, {
		{ name = "past a short history", rtt = 0.2, wait = 3, delay = 0.25, want = 94 },
	})

	if failure then
		return false, failure
	end

	return true, nil
end
