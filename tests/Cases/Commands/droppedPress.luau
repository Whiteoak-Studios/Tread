--[[
    A dropped press is never repeated: a stand-in after a command with a
    jump press and shots carries neither, and a discarded command's shots
    never carry into the next real command, reported as lateShot instead
--]]

--!strict
local Intake = require("../../Fixtures/Commands/Intake")

local START: number = 100 -- The first tick stepped

-- Shots, each a group the fixture game declares as a dropped list
local TWO_SHOTS: { { [string]: number } } = {
	{ sequence = 1, fraction = 0, yaw = 10, class = 1 },
	{ sequence = 2, fraction = 3, yaw = 20, class = 2 },
}

local ONE_SHOT: { { [string]: number } } = { { sequence = 3, fraction = -3, yaw = 30, class = 0 } }

return function (): (boolean, string | nil)
	local rig: Intake.Intake = Intake.new()
	rig:take(START)

	local firing: any = rig:command(START + 1)
	firing.jump = true
	firing.fields.shots = TWO_SHOTS
	rig:send({ firing })

	local real: any = rig:take(START + 1)
	if not real.pressed.jump or #real.fields.shots ~= #TWO_SHOTS then
		return false, `The real command ran with jump pressed {real.pressed.jump} and {#real.fields.shots} shots`
	end

	local standIn: any, isStandIn: boolean = rig:take(START + 2)
	if not isStandIn then
		return false, "A tick with no command ran something other than a stand-in"
	elseif standIn.jump or standIn.pressed.jump then
		return false, "A stand-in repeated the jump"
	elseif #standIn.fields.shots ~= 0 then
		return false, `A stand-in repeated {#standIn.fields.shots} shots`
	end

	-- 103 fires after its tick ran with a stand-in, and 104 is on time
	rig:take(START + 3)
	local commands: { any } = rig:commands(START + 4, 2)
	commands[2].fields.shots = ONE_SHOT
	rig:send(commands)

	local onTime: any = rig:take(START + 4)
	if #onTime.fields.shots ~= 0 then
		return false, `A discarded shot carried into the next real command, which fired {#onTime.fields.shots}`
	end

	local lateShots: { number | string } = rig:reported("lateShot")
	if #lateShots ~= 1 or lateShots[1] ~= #ONE_SHOT then
		return false, `The discarded shot was reported as {#lateShots} lateShot reports, not one of {#ONE_SHOT}`
	end

	return true, nil
end
