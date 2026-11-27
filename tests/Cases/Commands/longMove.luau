--[[
    A move input longer than 1 beyond rounding is reported as moveTamper
    with its command number and still runs, while a full input on one axis
    and a unit diagonal rounded to the wire's steps are not reported
--]]

--!strict
local Intake = require("../../Fixtures/Commands/Intake")

local START: number = 100 -- The tick stepped when the commands arrive
local FULL: number = 127 -- A move axis's wire steps at a full input
local DIAGONAL: number = 90 -- Each axis of a unit diagonal at those steps, rounded
local PAST: number = 91 -- One step more than that on one axis

-- Each command's wire move axes, and whether it is reported
type Case = { moveX: number, moveZ: number, reported: boolean }

local CASES: { Case } = {
	{ moveX = FULL, moveZ = 0, reported = false },
	{ moveX = DIAGONAL, moveZ = -DIAGONAL, reported = false },
	{ moveX = PAST, moveZ = DIAGONAL, reported = true },
	{ moveX = -FULL, moveZ = FULL, reported = true },
}

return function (): (boolean, string | nil)
	local rig: Intake.Intake = Intake.new()
	rig:take(START)

	for index: number, case: Case in CASES do
		local move: any = rig:encode({ rig:command(START + index) })
		move.commands[1].moveX = case.moveX
		move.commands[1].moveZ = case.moveZ
		rig:deliver()

		local reported: boolean = table.find(rig:reported("moveTamper"), START + index) ~= nil
		if reported ~= case.reported then
			return false, `A move of {case.moveX}, {case.moveZ} steps was reported {reported}, not {case.reported}`
		end
	end

	for index: number = 1, #CASES do
		local _: any, standIn: boolean = rig:take(START + index)
		if standIn then
			return false, `The command with move {CASES[index].moveX}, {CASES[index].moveZ} did not run`
		end
	end

	return true, nil
end
