--[[
    The step's own arithmetic: the one hand-written lerp every interpolation
    in Tread calls, the quantizers OwnerState's precisions need, and the fall
    a moved sleeper draws and is hit along
--]]

--!strict
--!native
local Constants = require(script.Parent.Parent.Constants)

local POSITION_STEPS: number = 1 / Constants.POSITION_QUANTUM -- Quanta a stud, so a quantized value is a whole count
local VELOCITY_STEPS: number = 1 / Constants.VELOCITY_QUANTUM
local EYE_STEPS: number = 1 / Constants.EYE_QUANTUM

local Math = {}

--[[
    Interpolates from a to b by t in plain arithmetic. Native code fuses
    math.lerp and vector.lerp and rounds them apart from interpreted code,
    so every realm calls this one instead and gets the same bits
--]]

function Math.lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

--[[
    Rounds a position axis or the fall apex to OwnerState's 1/512 stud, the
    precision every step's state ends on
--]]

function Math.quantize(value: number): number
	return math.round(value * POSITION_STEPS) / POSITION_STEPS
end

--[[
    Rounds a velocity axis to OwnerState's 1/64 stud a second
--]]

function Math.quantizeVelocity(value: number): number
	return math.round(value * VELOCITY_STEPS) / VELOCITY_STEPS
end

--[[
    Rounds the eased eye height or the mantle's rise to OwnerState's 1/32
    stud, the precision both ride in
--]]

function Math.quantizeEye(value: number): number
	return math.round(value * EYE_STEPS) / EYE_STEPS
end

--[[
    The place along a moved sleeper's fall from rest at from to to, elapsed
    seconds after it starts, and the fraction of the fall done. The drop
    takes sqrt(2h / gravity) for a drop of h; the horizontal place follows
    the fraction through lerp, and a move that isn't downward is done at once

    @ gravity | the shared table's step.gravity, studs/s², above 0
--]]

function Math.fall(from: vector, to: vector, gravity: number, elapsed: number): (vector, number)
	if not (gravity > 0) then
		error(`A fall needs a gravity above 0, and got {gravity}`)
	end

	local drop: number = from.y - to.y
	if drop <= 0 then
		return to, 1
	end

	-- From drop = gravity * duration² / 2
	local duration: number = math.sqrt(2 * drop / gravity)
	if elapsed >= duration then
		return to, 1
	elseif elapsed <= 0 then
		return from, 0
	end

	-- Falling from rest, the height lost goes with the fraction's square
	local fraction: number = elapsed / duration
	local x: number = Math.lerp(from.x, to.x, fraction)
	local y: number = from.y - drop * fraction * fraction
	local z: number = Math.lerp(from.z, to.z, fraction)

	return vector.create(x, y, z), fraction
end

return Math
