--[[
    Between predicted ticks the body draws between its last two by the
    clock's leftover fraction through Math.lerp, its eased eye height with
    it, and its facing between theirs on the shortest arc, across the wrap
    of a turn as well
--]]

--!strict
local Harness = require("../../Fixtures/Predict/Harness")

local QUARTER: number = math.pi / 2 -- A yaw that looks along -X
local NUDGE: number = 0.1 -- A small turn either side of a yaw of 0
local TURN: number = 2 * math.pi
local STEPS: number = 65536 -- A u16 angle's steps a turn

-- A facing's u16 steps, as the step rounds it
local function steps(facing: number): number
	return math.round(facing / TURN * STEPS) % STEPS
end

-- A walk ahead that turns to the given yaw from the third command on
local function turning(before: number, after: number): (command: any, count: number) -> ()
	return function (command: any, count: number)
		command.forward = 1
		command.fields.slot = 0
		command.fields.shots = {}
		command.yaw = before

		if count >= 3 then
			command.yaw = after
		end
	end
end

-- The facing between two on the shortest arc, as the drawn body takes it
local function between(rig: any, from: number, to: number, fraction: number): number
	local start: number = steps(from)
	local arc: number = (steps(to) - start + STEPS / 2) % STEPS - STEPS / 2

	return rig.Math.lerp(start, start + arc, fraction) * TURN / STEPS
end

return function (): (boolean, string | nil)
	local rig: any = Harness.new()
	local Math: any = rig.Math
	rig.input = turning(0, QUARTER)
	rig.spawn()
	rig.frames(3)

	local dt: number = rig.delta * 0.6
	local fraction: number = dt / rig.delta
	rig.frames(1, dt)

	local second: any = rig.twin(2)
	local third: any = rig.twin(3)
	local drawn: any = rig.Predict.state()
	local want: vector = vector.create(
		Math.lerp(second.position.x, third.position.x, fraction),
		Math.lerp(second.position.y, third.position.y, fraction),
		Math.lerp(second.position.z, third.position.z, fraction)
	)

	local facing: number = between(rig, second.facing, third.facing, fraction)
	if drawn.position ~= want then
		return false, `0.6 of a tick on, the body drew at {drawn.position}, not {want} between the last two ticks`
	elseif drawn.eyeHeight ~= Math.lerp(second.eyeHeight, third.eyeHeight, fraction) then
		return false, `The drawn eye height was {drawn.eyeHeight}, not between {second.eyeHeight} and {third.eyeHeight}`
	elseif drawn.facing ~= facing then
		return false, `The drawn facing was {drawn.facing}, not {facing}, 0.6 of the way into the quarter turn`
	end

	-- A turn from just left of a yaw of 0 to just right of it goes the short way, through 0 and not round through π
	local wrap: any = Harness.new()
	wrap.input = turning(-NUDGE, NUDGE)
	wrap.spawn()
	wrap.frames(3)
	wrap.frames(1, wrap.delta * 0.5)

	local across: number = between(wrap, wrap.twin(2).facing, wrap.twin(3).facing, 0.5)
	local drawnAcross: number = wrap.Predict.state().facing
	if drawnAcross ~= across or math.abs(math.sin(drawnAcross)) > NUDGE / 10 then
		return false, `Halfway across a yaw of 0 the drawn facing was {drawnAcross}, not {across} on the short arc`
	end

	return true, nil
end
