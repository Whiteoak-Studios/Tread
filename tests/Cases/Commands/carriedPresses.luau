--[[
    A discarded command's jump and crouch presses and carried fields, by OR
    or addition up to the field's most, reach the next real command, never
    a stand-in, and lapse past the stand-in window
--]]

--!strict
local Intake = require("../../Fixtures/Commands/Intake")

local START: number = 100 -- The first tick stepped
local USES_MOST: number = 9 -- The fixture game's carried counter's max

return function (): (boolean, string | nil)
	local rig: Intake.Intake = Intake.new()
	rig:take(START)
	rig:send({ rig:command(START + 1) })
	rig:take(START + 1)
	rig:take(START + 2)
	rig:take(START + 3)

	-- 102 presses jump and 103 crouch, each after its tick ran; 104 holds both, so it presses neither itself
	local commands: { any } = rig:commands(START + 4, 3)
	local own: any, crouching: any, jumping: any = commands[1], commands[2], commands[3]
	jumping.jump = true
	jumping.fields.reload = true
	jumping.fields.uses = 2
	crouching.jump = true
	crouching.crouch = true
	crouching.fields.uses = 3
	own.jump = true
	own.crouch = true
	own.fields.uses = 1
	rig:send(commands)

	local command: any, standIn: boolean = rig:take(START + 4)
	local pressed: any = command.pressed
	if standIn then
		return false, "The tick with a filed command ran a stand-in"
	elseif not pressed.jump or not pressed.crouch then
		return false, `The discarded presses did not carry: jump {pressed.jump}, crouch {pressed.crouch}`
	elseif command.fields.reload ~= true then
		return false, "A discarded true did not carry by OR"
	elseif command.fields.uses ~= 1 + 2 + 3 then
		return false, `The counters 1, 2 and 3 added to {command.fields.uses}, not 6`
	end

	-- A discarded 9 and a real 5 add past the field's most
	rig:take(START + 5)
	commands = rig:commands(START + 6, 2)
	commands[2].fields.uses = USES_MOST
	commands[1].fields.uses = 5
	rig:send(commands)

	command = rig:take(START + 6)
	if command.fields.uses ~= USES_MOST then
		return false, `A carried 9 and a real 5 gave {command.fields.uses}, where the field holds at most {USES_MOST}`
	elseif command.fields.reload ~= false then
		return false, "Two falses gave true by OR"
	end

	-- 107 presses jump after its tick, and no real command runs until 110, past the 2-tick window
	for tick: number = START + 7, START + 9 do
		rig:take(tick)
	end

	commands = rig:commands(START + 10, 4)
	commands[4].jump = true
	commands[4].fields.uses = 4
	rig:send(commands)

	command = rig:take(START + 10)
	if command.pressed.jump or command.fields.uses ~= 0 then
		return false, `A press from 3 ticks before the real command carried: jump {command.pressed.jump}`
	end

	-- 111 presses jump after its tick: the stand-in at 112 never takes it, and the real command at 113 does
	rig:take(START + 11)
	local pressing: any = rig:command(START + 11)
	pressing.jump = true
	rig:send({ pressing })

	local stood: any, isStandIn: boolean = rig:take(START + 12)
	if not isStandIn or stood.pressed.jump then
		return false, "A carried press reached a stand-in"
	end

	rig:send({ rig:command(START + 13) })
	command = rig:take(START + 13)
	if not command.pressed.jump then
		return false, "A press carried past a stand-in inside the window did not reach the next real command"
	end

	return true, nil
end
