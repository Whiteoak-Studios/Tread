--[[
    A Move with no commands is valid: it carries its acknowledgments and
    its delay, files nothing and reports nothing
--]]

--!strict
local Intake = require("../../Fixtures/Commands/Intake")

local START: number = 100 -- The tick stepped when the Move arrives
local ACKNOWLEDGED: number = 3
local RECEIVED: number = 0b101
local DELAY: number = 120 -- Milliseconds

return function (): (boolean, string | nil)
	local rig: Intake.Intake = Intake.new()
	rig:take(START)

	local reports: number = #rig.heard
	local move: any = rig:encode({}, ACKNOWLEDGED, RECEIVED, DELAY)
	if move.command ~= 0 or #move.commands ~= 0 then
		return false, `An empty Move went out numbered {move.command} with {#move.commands} commands`
	end

	rig:deliver()

	local sequence: number, mask: number = rig.Commands.acknowledged(rig.connection)
	if sequence ~= ACKNOWLEDGED or mask ~= RECEIVED or rig.Commands.delay(rig.connection) ~= DELAY then
		return false, `An empty Move's acknowledgments were not taken: {sequence}, {mask}`
	elseif rig.Commands.depth(rig.connection) ~= 0 then
		return false, "An empty Move filed a command"
	elseif #rig.heard ~= reports then
		return false, `An empty Move was reported as {rig.heard[#rig.heard].kind}`
	end

	local _: any, standIn: boolean = rig:take(START + 1)
	if not standIn then
		return false, "The tick after an empty Move ran something other than a stand-in"
	end

	return true, nil
end
