--[[
    A claimed render time inside the band, one tick plus two standard
    deviations of jitter and never wider than two, is used as claimed;
    one outside gives way to the expected time, with its offset. A claim's
    low 16 bits unwrap against the command's tick
--]]

--!strict
local Environment = require("../../Environment")

local HISTORY: string = "src/Server/History.luau"
local STATE: string = "src/Step/State.luau"
local EXAMPLE: string = "tests/Fixtures/Config/Example.luau"
local SLOT: number = 0
local TICK: number = 100 -- The command's tick, a relay tick too at the example's 20 and 20 Hz
local RTT: number = 0.1
local WAIT: number = 1 -- Simulation ticks, 0.05 s
local DELAY: number = 0.15
local EXPECTED: number = TICK - (RTT + WAIT / 20 + DELAY) * 20 -- 94, which no clamp moves
local FAR_TICK: number = 70000 -- Past the u16, where a claim's low 16 bits must unwrap
local WRAP: number = 65536
local NEAR: number = 1e-9

type Claim = { claimed: number, jitter: number, inside: boolean, name: string }

-- Writes the slot at every tick of the second before the tick, so the history's newest sample is the tick before
local function write(History: any, State: any, tick: number)
	local state = State.new()

	for at: number = tick - 20, tick - 1 do
		History.write(SLOT, at, state, 0)
	end
end

return function (): (boolean, string | nil)
	local History: any = Environment.load(HISTORY)
	local State: any = Environment.load(STATE)
	local Example: any = Environment.load(EXAMPLE)
	History.start(Example.shared(), Example.server())
	write(History, State, TICK)

	local claims: { Claim } = {
		{ claimed = EXPECTED + 0.75, jitter = 0, inside = true, name = "within the one tick" },
		{ claimed = EXPECTED - 0.9, jitter = 0, inside = true, name = "within it, early" },
		{ claimed = EXPECTED + 1.25, jitter = 0, inside = false, name = "past the one tick with no jitter" },
		{
			claimed = EXPECTED + 1.25,
			jitter = 0.0125,
			inside = true,
			name = "inside the 1.5 ticks jitter widens it to",
		},
		{ claimed = EXPECTED - 1.9, jitter = 1, inside = true, name = "inside the widest, two ticks" },
		{ claimed = EXPECTED + 2.1, jitter = 1, inside = false, name = "past the widest, however wide the jitter" },
	}

	for _, claim: Claim in claims do
		local time: number, inside: boolean, offset: number =
			History.rewindFor(TICK, RTT, claim.jitter, WAIT, DELAY, claim.claimed)
		local want: number = claim.inside and claim.claimed or EXPECTED

		if inside ~= claim.inside then
			return false, `A claim {claim.name}, at {claim.claimed}, read inside {inside}`
		elseif math.abs(time - want) > NEAR then
			return false, `A claim {claim.name}, at {claim.claimed}, rewound to {time}, not {want}`
		elseif math.abs(offset - (claim.claimed - EXPECTED)) > NEAR then
			return false, `A claim {claim.name} gave the offset {offset}, not {claim.claimed - EXPECTED}`
		end
	end

	-- A shot field's 16-bit render tick past the wrap reads as the full tick nearest the command's
	write(History, State, FAR_TICK)

	local full: number = FAR_TICK - (RTT + WAIT / 20 + DELAY) * 20 + 0.5
	local time: number, inside: boolean = History.rewindFor(FAR_TICK, RTT, 0, WAIT, DELAY, full % WRAP)
	if not inside or math.abs(time - full) > NEAR then
		return false, `A claim of {full % WRAP}, the low 16 bits of {full}, rewound to {time}, inside {inside}`
	end

	return true, nil
end
