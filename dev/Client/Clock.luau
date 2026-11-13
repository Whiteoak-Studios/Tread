--[[
    The dev replay's clock: the clip time a playback renders at, moved on
    each frame at its speed unless paused, stepped a relay tick at a time
    or sought, and held inside the clip
--]]

--!strict
local Clock = {}
Clock.__index = Clock

type Fields = {
	_time: number, -- Seconds since the clip's keyframe
	_length: number, -- Seconds the clip runs
	_interval: number, -- Seconds a relay tick, which a step moves
	_speeds: { number }, -- What the speed cycles through, its first the speed a clock starts at
	_speed: number, -- The speed's place in speeds
	_paused: boolean,
}

--[[
    A clock at the clip's start, playing at the first speed. It errors on a
    length below 0, an interval not above 0 and no speeds
--]]

function Clock.new(length: number, interval: number, speeds: { number }): Self
	if not (length >= 0) or not (interval > 0) or #speeds == 0 then
		local given: string = `{length}, {interval} and {#speeds} speeds`
		error(`Clock.new takes a length from 0, an interval above 0 and a speed, not {given}`, 2)
	end

	return setmetatable({
		_time = 0,
		_length = length,
		_interval = interval,
		_speeds = speeds,
		_speed = 1,
		_paused = false,
	}, Clock)
end

--[[
    Moves the time on by a frame of dt seconds at the speed unless paused,
    held at the clip's end, where it pauses. Gives the time
--]]

function Clock.advance(self: Self, dt: number): number
	if not self._paused then
		self._time = math.min(self._time + dt * self._speeds[self._speed], self._length)
	end

	if self._time >= self._length then
		self._paused = true
	end

	return self._time
end

-- Pauses a playing clock, or plays a paused one
function Clock.toggle(self: Self)
	self._paused = not self._paused
end

-- Moves the speed on to the next in its cycle, the last going round to the first
function Clock.cycle(self: Self)
	self._speed = self._speed % #self._speeds + 1
end

--[[
    Pauses and moves the time by so many relay ticks, back for a negative
    count, held inside the clip
--]]

function Clock.step(self: Self, ticks: number)
	self._paused = true
	self:_move(ticks * self._interval)
end

--[[
    Moves the time by so many seconds, back for a negative, held inside the
    clip, playing or paused as it was
--]]

function Clock.seek(self: Self, seconds: number)
	self:_move(seconds)
end

-- The clip time, seconds since the keyframe
function Clock.time(self: Self): number
	return self._time
end

-- Seconds the clip runs
function Clock.length(self: Self): number
	return self._length
end

-- The speed, a share of real time
function Clock.speed(self: Self): number
	return self._speeds[self._speed]
end

function Clock.paused(self: Self): boolean
	return self._paused
end

-- Whether the time stands at the clip's end
function Clock.ended(self: Self): boolean
	return self._time >= self._length
end

function Clock._move(self: Self, seconds: number)
	self._time = math.clamp(self._time + seconds, 0, self._length)
end

export type Clock = Self
type Self = typeof(setmetatable({} :: Fields, Clock))

return Clock
