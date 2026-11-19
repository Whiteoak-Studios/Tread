--[[
    Dropping a queue, as a teleport does, drops every waiting command and
    every press still to carry, a dropped command's copy never returns, and
    a removed connection keeps nothing
--]]

--!strict
local Intake = require("../../Fixtures/Commands/Intake")

local START: number = 100 -- The first tick stepped

return function (): (boolean, string | nil)
	local rig: Intake.Intake = Intake.new()
	local Commands: any = rig.Commands

	for tick: number = START, START + 2 do
		rig:take(tick)
	end

	-- 102 presses jump after its tick ran, which would carry into 104, and 103 waits
	local commands: { any } = rig:commands(START + 3, 2)
	commands[2].jump = true
	rig:send(commands, 6, 1, 150)

	if Commands.depth(rig.connection) ~= 1 then
		return false, `{Commands.depth(rig.connection)} commands wait before the drop, not 1`
	end

	Commands.drop(rig.connection)

	if Commands.depth(rig.connection) ~= 0 then
		return false, `{Commands.depth(rig.connection)} commands wait after the drop`
	end

	-- The copy of 103 stays dropped, and 104 is new
	rig:send(rig:commands(START + 4, 2))

	local _: any, dropped: boolean = rig:take(START + 3)
	if not dropped then
		return false, "Tick 103 ran the command dropped before it"
	end

	local after: any, standIn: boolean = rig:take(START + 4)
	if standIn then
		return false, "The command after the drop did not run"
	elseif after.pressed.jump then
		return false, "A press discarded before the drop carried past it"
	end

	Commands.remove(rig.connection)

	local sequence: number, mask: number = Commands.acknowledged(rig.connection)
	if sequence ~= 0 or mask ~= 0 or Commands.depth(rig.connection) ~= 0 or Commands.delay(rig.connection) ~= 0 then
		return false, "A removed connection kept its acknowledgments or its queue"
	end

	return true, nil
end
