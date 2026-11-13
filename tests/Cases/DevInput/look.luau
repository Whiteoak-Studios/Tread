--[[
    A drag turns the look as Tread's look does, right and up, short of
    straight up or down and the yaw inside a turn, the head level, each
    command carrying it, and a body's facing turning it back level
--]]

--!strict
local Harness = require("../../Fixtures/DevClient/Harness")

local INPUT: string = "dev/Client/Input.luau"
local RATE: number = 0.01 -- Radians a pixel turns in this case
local DRAG: number = 10 -- Pixels a small drag moves
local FAR: number = 1e6 -- Pixels a drag moves to run the pitch to its stop
local CONE: number = 75 -- The dev game's head cone, degrees
local FACING: number = 2 -- Radians, a body's facing
local ROUNDING: number = 1e-9

local TURN: number = 2 * math.pi
local QUARTER: number = math.pi / 2

return function (): (boolean, string | nil)
	local place: Harness.Game = Harness.new()
	local Input: any = place.load(INPUT)
	local Public: any = place.tread("Step.Public")
	local Command: any = place.tread("Codec.Command")

	local input: any = Input.new()
	local yaw: number, pitch: number, headYaw: number, headPitch: number = input:look()
	if yaw ~= 0 or pitch ~= 0 or headYaw ~= 0 or headPitch ~= 0 then
		return false, `A new input looked {yaw}, {pitch}, {headYaw}, {headPitch}, not level along -Z`
	end

	-- A drag right and up looks right of -Z, along +X, and above level
	input:turn(DRAG, -DRAG, RATE)
	yaw, pitch, headYaw, headPitch = input:look()
	local look: vector = Public.look(yaw, pitch, headYaw, headPitch, CONE)
	if not (look.x > 0 and look.y > 0 and look.z < 0) then
		return false, `A drag right and up looked along {look}, not right of -Z and up`
	elseif headYaw ~= 0 or headPitch ~= 0 then
		return false, `The head turned to {headYaw}, {headPitch} with no free look`
	end

	-- The yaw stays inside one turn either way
	if yaw < 0 or yaw >= TURN then
		return false, `A drag right left the yaw at {yaw}, outside 0 to a turn`
	end

	local command: any = Command.new()
	input:sample(command)
	if command.yaw ~= yaw or command.pitch ~= pitch then
		return false, `The command carried {command.yaw}, {command.pitch} where the frame looked {yaw}, {pitch}`
	end

	-- The pitch stops short of straight up and straight down
	input:turn(0, -FAR, RATE)
	local _, up: number = input:look()
	input:turn(0, FAR, RATE)
	local _, down: number = input:look()
	if not (up > 0 and up < QUARTER and down < 0 and down > -QUARTER and math.abs(up + down) < ROUNDING) then
		return false, `The pitch stopped at {up} up and {down} down, not short of a quarter turn each way`
	end

	-- A body's facing turns the look to it, level
	input:face(FACING + TURN)
	yaw, pitch = input:look()
	if math.abs(yaw - FACING) > ROUNDING or pitch ~= 0 then
		return false, `Facing {FACING} radians a turn on looked {yaw}, {pitch}, not {FACING} level`
	end

	return true, nil
end
