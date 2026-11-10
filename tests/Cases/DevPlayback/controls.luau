--[[
    The dev replay's clock gives known times: a pause holds it, half speed
    over a second moves half a second, a step moves one relay interval, a
    seek holds inside the clip at both ends, and its speeds cycle as set
--]]

--!strict
local Harness = require("../../Fixtures/DevClient/Harness")

local CLOCK: string = "dev/Client/Clock.luau"
local CONFIG: string = "dev/Client/Config.luau"
local LENGTH: number = 3 -- Seconds the clip runs
local INTERVAL: number = 1 / 20 -- Seconds a relay tick at the dev table's 20 Hz
local PLAYED: number = 0.5 -- Seconds played before the pause
local HELD: number = 1 -- Seconds of frames while paused
local AGAIN: number = 0.25 -- Seconds played once it plays again
local SECOND: number = 1 -- The second half speed plays over, and where a step starts
local SEEK: number = 1 -- Seconds a seek moves, as the replay's config sets it
local NEAR_START: number = 0.2 -- Seconds in, from where a seek back passes the start
local NEAR_END: number = 0.3 -- Seconds short of the end, from where a seek on passes it
local CLOSE: number = 1e-12 -- Seconds, past a float's rounding of the sums below

-- The speeds the replay's slow motion cycles through, the first the one a clip starts at
local SPEEDS: { number } = { 1, 0.5, 0.25 }

return function (): (boolean, string | nil)
	local place: Harness.Game = Harness.new()
	local Clock: any = place.load(CLOCK)
	local replay: any = place.load(CONFIG).replay
	local speeds: { number } = replay.speeds

	for index: number, speed: number in SPEEDS do
		if speeds[index] ~= speed or #speeds ~= #SPEEDS or replay.seek ~= SEEK then
			return false, `The replay's speeds are {table.concat(speeds, ", ")} and its seek {replay.seek} s`
		end
	end

	-- 1) A pause holds the time, and playing again moves it on from there
	local paused: any = Clock.new(LENGTH, INTERVAL, speeds)
	paused:advance(PLAYED)
	paused:toggle()
	paused:advance(HELD)
	if paused:time() ~= PLAYED or not paused:paused() then
		return false, `A clock paused at {PLAYED} s stood at {paused:time()} s {HELD} s later`
	end

	paused:toggle()
	paused:advance(AGAIN)
	if paused:time() ~= PLAYED + AGAIN or paused:paused() then
		return false, `Played again for {AGAIN} s from {PLAYED} s, the clock stood at {paused:time()} s`
	end

	-- 2) Half speed over a second moves half a second, and the speeds go round
	local slow: any = Clock.new(LENGTH, INTERVAL, speeds)
	slow:cycle()
	slow:advance(SECOND)
	if slow:speed() ~= SPEEDS[2] or slow:time() ~= SECOND * SPEEDS[2] then
		return false, `At {slow:speed()}x over {SECOND} s the clock moved to {slow:time()} s`
	end

	slow:cycle()
	local quarter: number = slow:speed()
	slow:cycle()
	if quarter ~= SPEEDS[3] or slow:speed() ~= SPEEDS[1] then
		return false, `The speed cycled on to {quarter} and then {slow:speed()}, not {SPEEDS[3]} and {SPEEDS[1]}`
	end

	-- 3) A step moves one relay interval either way and pauses
	local stepped: any = Clock.new(LENGTH, INTERVAL, speeds)
	stepped:advance(SECOND)
	stepped:step(1)
	if stepped:time() ~= SECOND + INTERVAL or not stepped:paused() then
		return false, `A step on from {SECOND} s stood at {stepped:time()} s, not {SECOND + INTERVAL} s and paused`
	end

	stepped:step(-1)
	if math.abs(stepped:time() - SECOND) > CLOSE then
		return false, `A step back stood at {stepped:time()} s, not {SECOND} s`
	end

	-- 4) A seek holds inside the clip at both ends, playing or paused as it was
	local seeking: any = Clock.new(LENGTH, INTERVAL, speeds)
	seeking:advance(NEAR_START)
	seeking:seek(-SEEK)
	if seeking:time() ~= 0 or seeking:paused() then
		return false, `A seek back {SEEK} s from {NEAR_START} s stood at {seeking:time()} s, or paused the clock`
	end

	seeking:advance(LENGTH - NEAR_END)
	seeking:seek(SEEK)
	if seeking:time() ~= LENGTH or not seeking:ended() then
		return false, `A seek on {SEEK} s from {LENGTH - NEAR_END} s stood at {seeking:time()} s, not the end`
	end

	-- 5) Play reaching the end holds there and pauses
	local ending: any = Clock.new(LENGTH, INTERVAL, speeds)
	if ending:advance(LENGTH + SECOND) ~= LENGTH or not ending:paused() or not ending:ended() then
		return false, `Played past its end, the clock stood at {ending:time()} s`
	end

	-- 6) A clock is refused an interval of 0, a length below 0 and no speeds
	local noInterval: boolean = pcall(Clock.new, LENGTH, 0, speeds)
	local backward: boolean = pcall(Clock.new, -LENGTH, INTERVAL, speeds)
	local unsped: boolean = pcall(Clock.new, LENGTH, INTERVAL, {})
	if noInterval or backward or unsped then
		return false, "A clock was made with an interval of 0, a length below 0 or no speeds"
	end

	return true, nil
end
