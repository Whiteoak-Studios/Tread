--[[
    The step's own arithmetic: the one hand-written lerp every interpolation
    in Tread calls, OwnerState's quantizers, the fall a moved sleeper draws
    and is hit along, and the sine and cosine in plain arithmetic
--]]

--!strict
--!native
local Constants = require(script.Parent.Parent.Constants)

local POSITION_STEPS: number = 1 / Constants.POSITION_QUANTUM -- Quanta a stud, so a quantized value is a whole count
local VELOCITY_STEPS: number = 1 / Constants.VELOCITY_QUANTUM
local EYE_STEPS: number = 1 / Constants.EYE_QUANTUM

-- The trig's series, each run on an angle reduced to within an eighth of a turn of a quarter turn's multiple
local QUARTER_TURN: number = math.pi / 2
local QUARTERS: number = 4 -- A turn's quarters, which pick the series and its sign
local SINE_TERMS: number = 7 -- Through x^15, whose next term stays under 5e-17 inside an eighth of a turn
local COSINE_TERMS: number = 8 -- Through x^16, the same reach

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

-- The sine of an angle within an eighth of a turn of 0, its Taylor series nested from the last term in
local function sineNear(angle: number): number
	local squared: number = angle * angle
	local sum: number = 1

	for term: number = SINE_TERMS, 1, -1 do
		sum = 1 - squared / ((2 * term) * (2 * term + 1)) * sum
	end

	return angle * sum
end

-- The cosine of an angle within an eighth of a turn of 0, the same way
local function cosineNear(angle: number): number
	local squared: number = angle * angle
	local sum: number = 1

	for term: number = COSINE_TERMS, 1, -1 do
		sum = 1 - squared / ((2 * term - 1) * (2 * term)) * sum
	end

	return sum
end

--[[
    The sine of an angle in radians in plain arithmetic, since the C
    library's may round apart between the server and a device. The angle is
    taken to its nearest quarter turn, and the series runs on what is left
--]]

function Math.sin(angle: number): number
	local quarter: number = math.round(angle / QUARTER_TURN)
	local left: number = angle - quarter * QUARTER_TURN
	local which: number = quarter % QUARTERS

	if which == 0 then
		return sineNear(left)
	elseif which == 1 then
		return cosineNear(left)
	elseif which == 2 then
		return -sineNear(left)
	end

	return -cosineNear(left)
end

--[[
    The cosine of an angle in radians, the same way as Math.sin
--]]

function Math.cos(angle: number): number
	local quarter: number = math.round(angle / QUARTER_TURN)
	local left: number = angle - quarter * QUARTER_TURN
	local which: number = quarter % QUARTERS

	if which == 0 then
		return cosineNear(left)
	elseif which == 1 then
		return -sineNear(left)
	elseif which == 2 then
		return -cosineNear(left)
	end

	return sineNear(left)
end

return Math
