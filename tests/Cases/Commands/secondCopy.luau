--[[
    A later copy that differs from the first, in Tread's or the game's
    fields, before or after it ran, is ignored and reported as moveTamper,
    while a matching copy and a stand-in never are
--]]

--!strict
local Intake = require("../../Fixtures/Commands/Intake")

local START: number = 100 -- The first tick stepped
local FIRST_YAW: number = 1 -- Radians, the first copy's
local OTHER_YAW: number = 2 -- A later copy's
local NEAR: number = 1e-3 -- Radians within a wire yaw step of the first copy's
-- A later copy's offset, the fixture game's last field: 0 sets the top bit of its packing above its lowest, so the
-- copy differs from the first only in the last byte its fields fill
local OTHER_OFFSET: number = 0

return function (): (boolean, string | nil)
	local rig: Intake.Intake = Intake.new()
	rig:take(START)

	local first: any = rig:command(START + 1)
	first.yaw = FIRST_YAW
	rig:send({ first })

	-- A second copy with another yaw, then one the same as the first
	local commands: { any } = rig:commands(START + 2, 2)
	commands[2].yaw = OTHER_YAW
	rig:send(commands)

	commands[2].yaw = FIRST_YAW
	rig:send(commands)

	local tampers: { number | string } = rig:reported("moveTamper")
	if #tampers ~= 1 or tampers[1] ~= START + 1 then
		return false, `A differing copy and a matching one gave {#tampers} moveTamper reports, not one for {START + 1}`
	end

	local ran: any = rig:take(START + 1)
	if math.abs(ran.yaw - FIRST_YAW) > NEAR then
		return false, `The command ran with yaw {ran.yaw}, where its first copy's was {FIRST_YAW}`
	end

	rig:take(START + 2)

	-- A copy that arrives after its first ran, with another game field
	commands = rig:commands(START + 3, 3)
	commands[3].yaw = FIRST_YAW
	commands[3].fields.offset = OTHER_OFFSET
	rig:send(commands)

	tampers = rig:reported("moveTamper")
	if #tampers ~= 2 or tampers[2] ~= START + 1 then
		return false, `A differing copy after its first ran gave {#tampers} moveTamper reports in all, not 2`
	end

	-- A first copy for a tick that ran a stand-in is late, not a tamper
	rig:take(START + 3)
	rig:take(START + 4)
	rig:send({ rig:command(START + 4) })

	if #rig:reported("moveTamper") ~= 2 then
		return false, "A command whose tick ran a stand-in was compared with the stand-in"
	elseif #rig:reported("late") ~= 1 then
		return false, "A command whose tick ran a stand-in was not reported late"
	end

	return true, nil
end
