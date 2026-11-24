--[[
    The send lag History.sendLag sets moves a rewind's expected time, its
    band and its reach back by exactly that lag, never past the ceiling; at
    0 every sum is today's, and a lag not finite or below 0 is refused
--]]

--!strict
local Environment = require("../../Environment")

local HISTORY: string = "src/Server/History.luau"
local STATE: string = "src/Step/State.luau"
local EXAMPLE: string = "tests/Fixtures/Config/Example.luau"
local SLOT: number = 0
local TICK: number = 100 -- The command's tick, a relay tick too at the example's 20 and 20 Hz
local RATE: number = 20 -- The example's simulation and relay rates, Hz
local QUEUE_WAIT: number = 3 -- The example's ticks.queueWait
local DELAY_MIN: number = 0.15 -- The example's rewind.delayMin and delayMax, seconds
local DELAY_MAX: number = 0.25
local SEND_LAG: number = 0.036 -- Seconds, 0.72 relay ticks
local SHIFT: number = SEND_LAG * RATE -- The relay ticks the expected time and the reach move back by
local TODAY: number = 94 -- A good connection's expected time with no send lag, 100 less 0.3 s of relay ticks
local MOVED: number = TODAY - SHIFT
local FAR: number = 0 -- A claim far outside any band, so a rewind gives the expected time as the reach holds it
local NEAR: number = 1e-9

type Shot = {
	name: string,
	rtt: number,
	jitter: number,
	wait: number,
	delay: number,
	claimed: number,
	inside: boolean,
	want: number,
}

-- The history's lag with no send lag set: the round trip, the capped wait and the clamped delay
local function lagOf(shot: Shot): number
	return shot.rtt + math.min(shot.wait, QUEUE_WAIT) / RATE + math.clamp(shot.delay, DELAY_MIN, DELAY_MAX)
end

-- A history started on the example with the slot written at every tick of the second before the command's
local function started(): any
	local Example: any = Environment.load(EXAMPLE)
	local State: any = Environment.load(STATE)
	local History: any = Environment.load(HISTORY)
	History.start(Example.shared(), Example.server())

	local state = State.new()
	for at: number = TICK - RATE, TICK - 1 do
		History.write(SLOT, at, state, 0)
	end

	return History
end

return function (): (boolean, string | nil)
	-- Each want is the shot's rewind with the send lag set
	local shots: { Shot } = {
		{
			name = "at the moved expected time",
			rtt = 0.1,
			jitter = 0,
			wait = 1,
			delay = 0.15,
			claimed = MOVED,
			inside = true,
			want = MOVED,
		},
		{
			name = "early in the moved band",
			rtt = 0.1,
			jitter = 0,
			wait = 1,
			delay = 0.15,
			claimed = MOVED - 0.9,
			inside = true,
			want = MOVED - 0.9,
		},
		{
			name = "late in the moved band",
			rtt = 0.1,
			jitter = 0,
			wait = 1,
			delay = 0.15,
			claimed = MOVED + 0.9,
			inside = true,
			want = MOVED + 0.9,
		},
		{
			name = "late in today's band, past the moved one",
			rtt = 0.1,
			jitter = 0,
			wait = 1,
			delay = 0.15,
			claimed = TODAY + 0.9,
			inside = false,
			want = MOVED,
		},
		{
			name = "past the moved band",
			rtt = 0.1,
			jitter = 0,
			wait = 1,
			delay = 0.15,
			claimed = MOVED + 1.25,
			inside = false,
			want = MOVED,
		},
		{
			name = "at the early edge of the widest band, which the moved reach still reaches",
			rtt = 0.1,
			jitter = 1,
			wait = 1,
			delay = 0.15,
			claimed = MOVED - 1.9,
			inside = true,
			want = MOVED - 1.9,
		},
		{
			name = "past the RTT cap, held by the moved reach",
			rtt = 0.4,
			jitter = 0,
			wait = 0,
			delay = 0.15,
			claimed = FAR,
			inside = false,
			want = 91 - SHIFT,
		},
		{
			name = "past the ceiling, which never moves",
			rtt = 1,
			jitter = 0,
			wait = 3,
			delay = 0.25,
			claimed = FAR,
			inside = false,
			want = 90,
		},
	}

	local today: any = started()
	local lagged: any = started()

	if today.sendLagSeconds() ~= 0 then
		return false, `A started history's send lag reads {today.sendLagSeconds()}, not 0`
	end

	for _, shot: Shot in shots do
		local lag: number = today.lag(shot.rtt, shot.wait, shot.delay)
		if lag ~= lagOf(shot) then
			return false, `With no send lag a shot {shot.name} lags {lag} s, not today's {lagOf(shot)}`
		end
	end

	lagged.sendLag(SEND_LAG)
	if lagged.sendLagSeconds() ~= SEND_LAG then
		return false, `A send lag set to {SEND_LAG} s reads {lagged.sendLagSeconds()}`
	end

	for _, shot: Shot in shots do
		local lag: number = lagged.lag(shot.rtt, shot.wait, shot.delay)
		local time: number, inside: boolean, offset: number =
			lagged.rewindFor(TICK, shot.rtt, shot.jitter, shot.wait, shot.delay, shot.claimed)
		local expected: number = TICK - (lagOf(shot) + SEND_LAG) * RATE

		if math.abs(lag - (lagOf(shot) + SEND_LAG)) > NEAR then
			return false, `With the send lag a shot {shot.name} lags {lag} s, not {lagOf(shot) + SEND_LAG}`
		elseif inside ~= shot.inside then
			return false, `With the send lag a shot {shot.name}, at {shot.claimed}, read inside {inside}`
		elseif math.abs(time - shot.want) > NEAR then
			return false, `With the send lag a shot {shot.name}, at {shot.claimed}, rewound to {time}, not {shot.want}`
		elseif math.abs(offset - (shot.claimed - expected)) > NEAR then
			return false, `With the send lag a shot {shot.name} gave the offset {offset}, not {shot.claimed - expected}`
		end
	end

	local refusals: { [string]: any } = {
		["A negative send lag"] = -0.01,
		["A NaN send lag"] = 0 / 0,
		["An infinite send lag"] = math.huge,
		["A send lag given as a string"] = "0.01",
	}

	for name: string, seconds: any in refusals do
		local passed: boolean, failure: any = pcall(lagged.sendLag, seconds)
		if passed then
			return false, `{name} was taken`
		elseif not string.find(tostring(failure), "finite number of 0 or more", 1, true) then
			return false, `{name} was refused as "{failure}", which doesn't say what it takes`
		elseif lagged.sendLagSeconds() ~= SEND_LAG then
			return false, `{name} left the send lag at {lagged.sendLagSeconds()} s, not {SEND_LAG}`
		end
	end

	-- Set back to 0, every sum and every rewind is today's, bit for bit
	lagged.sendLag(0)

	for _, shot: Shot in shots do
		local time: number, inside: boolean, offset: number =
			lagged.rewindFor(TICK, shot.rtt, shot.jitter, shot.wait, shot.delay, shot.claimed)
		local todayTime: number, todayInside: boolean, todayOffset: number =
			today.rewindFor(TICK, shot.rtt, shot.jitter, shot.wait, shot.delay, shot.claimed)

		if lagged.lag(shot.rtt, shot.wait, shot.delay) ~= lagOf(shot) then
			return false, `With the send lag back at 0 a shot {shot.name} lags apart from today's`
		elseif time ~= todayTime or inside ~= todayInside or offset ~= todayOffset then
			return false,
				`With the send lag back at 0 a shot {shot.name} rewound to {time}, {inside}, {offset}, not today's {todayTime}, {todayInside}, {todayOffset}`
		end
	end

	return true, nil
end
