--[[
    While the live panel shows, a turn by the mouse or a drag leaves the
    dev input's look where it was, each command carrying that look, and
    once the panel hides the same turn moves it again
--]]

--!strict
local Harness = require("../../Fixtures/DevClient/Harness")

local INPUT: string = "dev/Client/Input.luau"
local RATE: number = 0.01 -- Radians a pixel turns in this case
local DRAG: number = 10 -- Pixels a drag moves

return function (): (boolean, string | nil)
	local place: Harness.Game = Harness.new()
	local Input: any = place.load(INPUT)
	local Command: any = place.tread("Codec.Command")

	-- Stands in for the panel's open, which the dev client hands its input
	local shown: boolean = false
	local input: any = Input.new(function (): boolean
		return shown
	end)

	-- 1) Shown, a drag right and up turns nothing, and the command carries the look as it was
	input:turn(DRAG, DRAG, RATE)
	local yaw: number, pitch: number = input:look()

	shown = true
	input:turn(DRAG, -DRAG, RATE)
	local heldYaw: number, heldPitch: number = input:look()
	if heldYaw ~= yaw or heldPitch ~= pitch then
		return false, `With the panel shown a drag turned the look from {yaw}, {pitch} to {heldYaw}, {heldPitch}`
	end

	local command: any = Command.new()
	input:sample(command)
	if command.yaw ~= yaw or command.pitch ~= pitch then
		return false, `With the panel shown the command carried {command.yaw}, {command.pitch}, not {yaw}, {pitch}`
	end

	-- 2) Hidden again, the same drag turns it
	shown = false
	input:turn(DRAG, -DRAG, RATE)
	local movedYaw: number, movedPitch: number = input:look()
	if movedYaw == yaw or movedPitch == pitch then
		return false, `With the panel hidden a drag left the look at {movedYaw}, {movedPitch}`
	end

	-- 3) An input given no hold always turns, as the dev client's cases make theirs
	local free: any = Input.new()
	free:turn(DRAG, -DRAG, RATE)
	local freeYaw: number = free:look()
	if freeYaw == 0 then
		return false, "An input given no hold did not turn"
	end

	return true, nil
end
