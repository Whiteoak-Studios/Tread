--[[
    The sample gives the dev game's command fields empty hands and no shots,
    making a shot list once per command and keeping it after, and leaves the
    lean and head offset Tread put at rest alone
--]]

--!strict
local Harness = require("../../Fixtures/DevClient/Harness")

local INPUT: string = "dev/Client/Input.luau"
local SAMPLES: number = 3

return function (): (boolean, string | nil)
	local place: Harness.Game = Harness.new()
	local Input: any = place.load(INPUT)
	local Command: any = place.tread("Codec.Command")

	local input: any = Input.new()
	input:press("W", true)

	local command: any = Command.new()
	input:sample(command)

	local shots: any = command.fields.shots
	if command.fields.slot ~= 0 then
		return false, `The sample held slot {command.fields.slot}, not the empty hands' 0`
	elseif type(shots) ~= "table" or #shots ~= 0 then
		return false, `The sample's shots were {shots}, not an empty list`
	elseif command.lean ~= 0 or command.headYaw ~= 0 or command.headPitch ~= 0 then
		return false, `The sample moved the lean or head offset Tread had at rest`
	end

	for _ = 1, SAMPLES do
		input:sample(command)
		if command.fields.shots ~= shots then
			return false, "A later sample made the command a new shot list"
		end
	end

	-- A command made afresh gets a list of its own
	local other: any = Command.new()
	input:sample(other)
	if other.fields.shots == shots or type(other.fields.shots) ~= "table" then
		return false, "A second command shared the first's shot list"
	end

	return true, nil
end
