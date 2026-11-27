--[[
    Commands.look is nil until a command is filed, then the newest command's
    yaw turned by its head offset, held to the head cone, on the ground: an
    older command, a later copy and a pitch change nothing, and a command
    too late for the ring but newer than every one before still counts
--]]

--!strict
local Environment = require("../../Environment")
local Intake = require("../../Fixtures/Commands/Intake")

local CONSTANTS: string = "src/Constants.luau"
local START: number = 100 -- The first tick stepped
local CONE: number = 75 -- The example's step.headCone, degrees
local NEAR: number = 1e-3 -- Within a wire yaw step, about 1e-4 radians
local YAW: number = 1 -- Radians, the first command's base yaw
local OLDER_YAW: number = 2
local COPY_YAW: number = 3
local NEWER_YAW: number = 0.5
local LATE_YAW: number = -1
local PAST_CONE: number = 120 -- A head offset past the cone, which is held to it
local PITCH: number = 0.6 -- Radians
local HEAD_PITCH: number = 40 -- Degrees

-- The look on the ground a base yaw in radians and a head offset in degrees give
local function expected(yaw: number, head: number): vector
	local turned: number = yaw + math.rad(head)

	return vector.create(-math.sin(turned), 0, -math.cos(turned))
end

-- Why a look differs from the one expected, or nil when it matches
local function differs(look: vector?, wanted: vector): string?
	if look == nil then
		return "there was none"
	elseif look.y ~= 0 then
		return `it had a height of {look.y}`
	elseif math.abs(look.x - wanted.x) > NEAR or math.abs(look.z - wanted.z) > NEAR then
		return `it was ({look.x}, {look.z}), not ({wanted.x}, {wanted.z})`
	end

	return nil
end

return function (): (boolean, string | nil)
	local Constants: any = Environment.load(CONSTANTS)
	local rig: Intake.Intake = Intake.new()
	local Commands: any = rig.Commands

	if Commands.look(rig.connection) ~= nil then
		return false, "A connection with no Move had a look"
	end

	-- Before the first tick no command is filed, so no look is kept
	rig:send({ rig:command(START) })
	if Commands.look(rig.connection) ~= nil then
		return false, "A Move before the first tick gave a look"
	end

	rig:take(START)

	local first: any = rig:command(START + 3)
	first.yaw = YAW
	first.headYaw = -CONE
	rig:send({ first })

	local problem: string? = differs(Commands.look(rig.connection), expected(YAW, -CONE))
	if problem then
		return false, `The first command's look was wrong: {problem}`
	end

	-- An older command arriving after it, and a later copy of it that differs, keep its look
	local older: any = rig:command(START + 2)
	older.yaw = OLDER_YAW
	rig:send({ older })

	local copy: any = rig:command(START + 3)
	copy.yaw = COPY_YAW
	rig:send({ copy })

	problem = differs(Commands.look(rig.connection), expected(YAW, -CONE))
	if problem then
		return false, `After an older command and a differing copy, the look was wrong: {problem}`
	end

	-- A newer one's look holds its head offset to the cone
	local newer: any = rig:command(START + 4)
	newer.yaw = NEWER_YAW
	newer.headYaw = PAST_CONE
	rig:send({ newer })

	problem = differs(Commands.look(rig.connection), expected(NEWER_YAW, CONE))
	if problem then
		return false, `A head offset past the cone gave the wrong look: {problem}`
	end

	-- Its pitch, raised by its head pitch, leaves the look on the ground
	local raised: any = rig:command(START + 5)
	raised.yaw = NEWER_YAW
	raised.pitch = PITCH
	raised.headPitch = HEAD_PITCH
	rig:send({ raised })

	problem = differs(Commands.look(rig.connection), expected(NEWER_YAW, 0))
	if problem then
		return false, `A raised look was not kept on the ground: {problem}`
	end

	-- Far enough on that the next command is older than the ring holds, yet newer than every one filed
	local behind: number = math.max(Constants.MAX_COMMANDS, rig.shared.ticks.standIn + 1)
	rig:take(START + 6 + behind)

	local late: any = rig:command(START + 6)
	late.yaw = LATE_YAW
	rig:send({ late })

	problem = differs(Commands.look(rig.connection), expected(LATE_YAW, 0))
	if problem then
		return false, `A command too late for the ring gave the wrong look: {problem}`
	elseif #rig:reported("late") ~= 1 then
		return false, `The command too late for the ring gave {#rig:reported("late")} late reports, not 1`
	end

	return true, nil
end
