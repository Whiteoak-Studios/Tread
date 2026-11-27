--[[
    A deferred tick keeps one entry in its split stage's ring, made at the
    Heartbeat its rest runs in and holding the early part's time and the
    run's together, so every stage still keeps one entry a tick
--]]

--!strict
local Split = require("../../Fixtures/Server/Split")

local CALM_TICKS: number = 3 -- The calm ticks before a tick that defers
local DEFERRALS: number = 3 -- The deferred ticks the case runs
local QUARTER: number = 0.25 -- A Heartbeat's share of a tick that owes none
local HALF: number = 0.5 -- The share that begins the next calm tick
local SPIN: number = 0.005 -- Seconds the early part and the split stage's run each hold the loop
local BOTH: number = SPIN * 1.5 -- Below the two parts' spins together, and above either one's alone

return function (): (boolean, string | nil)
	local loop: Split.Loop = Split.new()
	local Tick: any = loop.Tick
	Tick.useSplit(true)
	Split.calm(loop, CALM_TICKS)

	local stage: any = Split.stage(loop)
	local beats: { [number]: number } = {} -- The Heartbeat each deferred tick's rest ran in
	loop.spins.early = SPIN
	loop.spins.split = SPIN

	for tick: number = CALM_TICKS + 1, CALM_TICKS + DEFERRALS do
		Split.beat(loop, QUARTER)
		if tick > CALM_TICKS + 1 then
			beats[tick - 1] = Tick.heartbeats().count
		end

		Split.beat(loop, QUARTER)

		-- 1) The early part leaves no entry of its own: the ring's newest is still the tick before
		local got: string = Split.beat(loop, HALF)
		local newest: number = stage.ticks[stage.held]
		if got ~= `before {tick}, slices {tick}, early {tick}` or newest ~= tick - 1 then
			return false, `Deferring tick {tick} ran {got}, and the ring's newest entry is for tick {newest}`
		end
	end

	local last: number = CALM_TICKS + DEFERRALS
	Split.beat(loop, QUARTER)
	beats[last] = Tick.heartbeats().count
	Split.beat(loop, QUARTER)

	-- 2) Each stage but the between one, which runs every Heartbeat, keeps one entry a tick, in order, and the split
	-- stage's last is its newest
	for _, each: any in Tick.stages() do
		if each.between then
			continue
		elseif each.held ~= last then
			return false, `The {each.name} stage keeps {each.held} entries over {last} ticks`
		end

		for index: number = 1, each.held do
			if each.ticks[index] ~= index then
				return false, `The {each.name} stage's entry {index} is for tick {each.ticks[index]}`
			end
		end
	end

	if stage.last ~= stage.times[last] then
		return false, `The split stage's last is {stage.last}, not its newest entry's {stage.times[last]}`
	end

	-- 3) A deferred tick's entry holds both parts' time and carries the Heartbeat its rest ran in
	for tick: number = CALM_TICKS + 1, last do
		if not (stage.times[tick] >= BOTH) then
			return false, `Deferred tick {tick}'s entry holds {stage.times[tick]} s, under its two parts' {2 * SPIN}`
		elseif stage.beats[tick] ~= beats[tick] then
			return false,
				`Deferred tick {tick}'s entry came in Heartbeat {stage.beats[tick]}, not its rest's {beats[tick]}`
		end
	end

	return true, nil
end
