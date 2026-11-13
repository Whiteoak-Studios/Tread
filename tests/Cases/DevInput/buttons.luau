--[[
    Space, left Shift, C and the right mouse button hold the jump, sprint,
    crouch and aim levels while down, and the sampled command crosses
    Tread's wire under the dev declarations and reads back the same
--]]

--!strict
local Harness = require("../../Fixtures/DevClient/Harness")
local Shared = require("../../Fixtures/DevShared/Harness")

local INPUT: string = "dev/Client/Input.luau"

-- Each binding and the command level it holds
local BUTTONS: { Button } = {
	{ name = "Space", level = "jump" },
	{ name = "LeftShift", level = "sprint" },
	{ name = "C", level = "crouch" },
	{ name = "MouseButton2", level = "aim" },
}

local LEVELS: { string } = { "jump", "sprint", "crouch", "aim" }

type Button = { name: string, level: string }

return function (): (boolean, string | nil)
	local shared: any = Shared.load().shared
	local place: Harness.Game = Harness.new()
	local Input: any = place.load(INPUT)
	local Command: any = place.tread("Codec.Command")
	local Fields: any = place.tread("Codec.Fields")

	local layout: any = Fields.compile(shared.fields)
	local limits: any = { lean = shared.step.lean, headCone = shared.step.headCone }

	for _, button: Button in BUTTONS do
		local input: any = Input.new()
		input:press(button.name, true)

		local command: any = Command.new()
		input:sample(command)

		for _, level: string in LEVELS do
			local wanted: boolean = level == button.level
			if command[level] ~= wanted then
				return false, `{button.name} held sampled {level} as {command[level]}, not {wanted}`
			end
		end

		-- The command crosses the wire as Predict sends it, and reads back with its level and the dev game's fields
		local wire: any = Command.wire()
		local wrote: boolean, failure: any = pcall(Command.write, command, wire, layout, limits)
		if not wrote then
			return false, `The command {button.name} sampled didn't cross the wire: {failure}`
		end

		local read: any = Command.new()
		local failed: number? = Command.read(wire, read, layout, limits)
		if failed ~= nil then
			return false, `The command {button.name} sampled read back failing at field {failed}`
		elseif read[button.level] ~= true then
			return false, `The command read back without {button.level}, which {button.name} held`
		elseif read.fields.slot ~= 0 or #read.fields.shots ~= 0 then
			return false, `The command read back holding slot {read.fields.slot} and {#read.fields.shots} shots`
		end

		input:press(button.name, false)
		input:sample(command)
		if command[button.level] then
			return false, `{button.name} let go still sampled {button.level}`
		end
	end

	return true, nil
end
