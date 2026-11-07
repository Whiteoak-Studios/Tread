--[[
    The dev game's keys and move stick fill a command's move axes: each key
    alone a full input, opposed keys nothing, a diagonal or a key on top of
    the stick held to a length of 1, and an unbound key moving nothing
--]]

--!strict
local Harness = require("../../Fixtures/DevClient/Harness")

local INPUT: string = "dev/Client/Input.luau"
local ROUNDING: number = 1e-9 -- How far a scaled axis may sit from its exact value
local DIAGONAL: number = math.sqrt(0.5) -- Each axis of a full diagonal input

local CASES: { Case } = {
	{ keys = {}, forward = 0, right = 0, label = "nothing held" },
	{ keys = { "W" }, forward = 1, right = 0, label = "W" },
	{ keys = { "S" }, forward = -1, right = 0, label = "S" },
	{ keys = { "D" }, forward = 0, right = 1, label = "D" },
	{ keys = { "A" }, forward = 0, right = -1, label = "A" },
	{ keys = { "W", "S" }, forward = 0, right = 0, label = "W and S" },
	{ keys = { "W", "D" }, forward = DIAGONAL, right = DIAGONAL, label = "W and D" },
	{ keys = { "S", "A" }, forward = -DIAGONAL, right = -DIAGONAL, label = "S and A" },
	{ keys = { "Q", "Unknown", "Keyboard" }, forward = 0, right = 0, label = "unbound keys" },
	{ keys = {}, stick = { 0.5, 0 }, forward = 0, right = 0.5, label = "the stick half right" },
	{ keys = {}, stick = { 0, 3 }, forward = 1, right = 0, label = "the stick past its rim" },
	{ keys = {}, stick = { 2, 2 }, forward = DIAGONAL, right = DIAGONAL, label = "the stick past its rim at 45°" },
	{ keys = { "W" }, stick = { 0, 0.5 }, forward = 1, right = 0, label = "W over the stick" },
	{ keys = { "W" }, stick = { 1, 0 }, forward = DIAGONAL, right = DIAGONAL, label = "W and the stick right" },
}

type Case = { keys: { string }, stick: { number }?, forward: number, right: number, label: string }

return function (): (boolean, string | nil)
	for _, case: Case in CASES do
		local place: Harness.Game = Harness.new()
		local Input: any = place.load(INPUT)
		local Command: any = place.tread("Codec.Command")

		local input: any = Input.new()
		for _, key: string in case.keys do
			input:press(key, true)
		end

		local stick: { number }? = case.stick
		if stick then
			input:stick(stick[1], stick[2])
		end

		local command: any = Command.new()
		input:sample(command)

		local forward: number, right: number = command.forward, command.right
		local length: number = math.sqrt(forward * forward + right * right)
		if math.abs(forward - case.forward) > ROUNDING or math.abs(right - case.right) > ROUNDING then
			local wanted: string = `{case.forward} and {case.right}`
			return false, `{case.label} sampled forward {forward} and right {right}, not {wanted}`
		elseif length > 1 + ROUNDING then
			return false, `{case.label} sampled a move {length} long, past a full input`
		end

		-- Letting go of every key leaves only the stick
		for _, key: string in case.keys do
			input:press(key, false)
		end

		input:stick(0, 0)
		input:sample(command)
		if command.forward ~= 0 or command.right ~= 0 then
			return false, `{case.label} let go still sampled {command.forward} and {command.right}`
		end
	end

	return true, nil
end
