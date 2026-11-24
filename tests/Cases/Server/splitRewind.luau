--[[
    The history's send term reaches server:rewindFor and a tap frame's view
    lag, on a stand-in clock: with the split on and a finish's measure in,
    both move by the term against a server without the split; with it off
    both are that server's; and a rewind still stops at rewind.ceiling
--]]

--!strict
local SplitSide = require("../../Fixtures/Server/SplitSide")

local ON_AT: number = SplitSide.CALM + 1 -- A deferred tick, read with the split on
local OFF_AT: number = ON_AT + 1 -- The tick after the split goes off
local JUMP: number = 10 -- Seconds the stand-in clock moves before a finish, so one measure lifts the term past the cap
local MILLISECONDS: number = 1000 -- A second's, which a frame's view lag counts in
local ROUNDING: number = 1 -- Milliseconds a frame's lag may part from the term by, each lag rounded to one
local TOLERANCE: number = 1e-9 -- Relay ticks two rewinds of the same exact sums may part by

type Driven = SplitSide.Driven

-- A side on the workers with checks and the stand-in clock, the split as given
local function build(split: boolean): Driven
	return SplitSide.new({ split = split, workers = true, checks = true, clock = true })
end

-- The view lag, in ms, of the client's tap frame for a tick
local function lagOf(driven: Driven, tick: number): number?
	for _, data: string in driven.side.frames.Client do
		local frame: any = driven.side.Tap.read(buffer.fromstring(data))
		if frame.tick == tick and frame.owner then
			return frame.owner.lag
		end
	end

	return nil
end

-- The client's rewind for its command of a tick, claimed at that tick, which the band's width puts outside it
local function rewound(driven: Driven, tick: number): number
	local side: any = driven.side

	return (side.server:rewindFor(side.keys.Client, tick, tick))
end

return function (): (boolean, string | nil)
	local on: Driven = build(true)
	local off: Driven = build(false)
	local rate: number = on.side.rig.shared.rates.relay
	local ceiling: number = on.side.rig.settings.rewind.ceiling
	local History: any = on.side.rig:require(on.side.rig.tread.Server.History)

	SplitSide.ticks(on, ON_AT)
	SplitSide.ticks(off, ON_AT)

	-- With the split on, the term the tick's decode set moves the rewind and the frame's lag by itself
	local term: number = History.sendLagSeconds()
	local moved: number = rewound(off, ON_AT) - rewound(on, ON_AT)
	local lagOn: number?, lagOff: number? = lagOf(on, ON_AT), lagOf(off, ON_AT)

	if term == 0 then
		return false, `The history's term was 0 at tick {ON_AT}, deferred with the split on`
	elseif math.abs(moved - term * rate) > TOLERANCE then
		return false, `The rewind moved {moved} relay ticks with a term of {term} s, not {term * rate}`
	elseif not lagOn or not lagOff or math.abs(lagOn - lagOff - term * MILLISECONDS) > ROUNDING then
		return false,
			`The frame's view lag was {lagOn} ms with the term and {lagOff} without, not {term * MILLISECONDS} apart`
	end

	-- With it off, from the next tick's decode, both are the server's without the split
	on.side.Tick.useSplit(false)
	SplitSide.ticks(on, 1)
	SplitSide.ticks(off, 1)

	if rewound(on, OFF_AT) ~= rewound(off, OFF_AT) or lagOf(on, OFF_AT) ~= lagOf(off, OFF_AT) then
		local rewinds: string = `{rewound(on, OFF_AT)} and {rewound(off, OFF_AT)}`
		return false,
			`With the split off the rewinds were {rewinds} and the lags {lagOf(on, OFF_AT)} and {lagOf(off, OFF_AT)}`
	end

	-- A deferred tick's finish measured past JUMP seconds lifts the term, and the next tick's rewind stops at the cap
	local base: number = OFF_AT - rewound(off, OFF_AT) -- The rewind's relay ticks without any term
	on.side.Tick.useSplit(true)
	local tick: number = OFF_AT + 1
	on.file(tick)
	SplitSide.beat(on, SplitSide.THIRD)
	SplitSide.beat(on, SplitSide.THIRD)
	local clock: { now: number } = on.clock :: { now: number }
	clock.now += JUMP
	SplitSide.beat(on, SplitSide.THIRD)

	on.file(tick + 1)
	SplitSide.beat(on, SplitSide.THIRD)

	local lifted: number = History.sendLagSeconds()
	local capped: number = rewound(on, tick + 1)
	if base + lifted * rate <= ceiling * rate then
		return false, `The lifted term, {lifted} s, left the rewind inside the cap, so the case shows nothing of it`
	elseif capped ~= tick + 1 - ceiling * rate then
		return false, `The rewind past the cap gave {capped}, not {tick + 1 - ceiling * rate}`
	end

	return true, nil
end
