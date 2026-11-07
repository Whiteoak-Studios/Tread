--[[
    A landing that counts reaches the landing callback with its NPC and
    speed, and an NPC no spot frees is reported stuck, with no player, at
    its spawn and at a step whose depenetration finds it
--]]

--!strict
local Environment = require("../../Environment")

local STAGE: string = "tests/Fixtures/Npcs/Stage.luau"
local DROP: number = 10 -- Studs above the floor it falls from
local FALL_TICKS: number = 40
local EXACT_TICK: number = 50 -- A tick whose command number runs the exact overlap that finds the vault

return function (): (boolean, string | nil)
	local stage: any = Environment.load(STAGE)
	stage.start()

	local settings: any = stage.world.settings
	local faller: any = stage.Npcs.create(vector.create(-20, stage.geometry.floor + DROP, -14), 0)

	for tick: number = 1, FALL_TICKS do
		stage.Npcs.step(tick)
	end

	-- A fall from 10 studs meets the ground faster than any jump on level ground lands
	local fastestJump: number = settings.jump + settings.gravity * stage.world.delta
	if #stage.landings ~= 1 then
		return false, `A fall of {DROP} studs gave {#stage.landings} landings, not one`
	elseif stage.landings[1].npc ~= faller or not (stage.landings[1].speed > fastestJump) then
		return false, `The landing reached its callback as {stage.landings[1].speed} studs a second, not this fall's`
	elseif #stage.reports ~= 0 then
		return false, `A clean fall gave {#stage.reports} reports`
	end

	-- Inside the vault, where no spot the depenetration tries is clear
	local vault: any = stage.geometry.vault
	local buried: any = stage.Npcs.create(vector.create(vault.center.x, stage.geometry.floor + 3, vault.center.z), 0)
	if #stage.reports ~= 1 then
		return false, `An NPC made inside the vault gave {#stage.reports} reports at its spawn, not one`
	end

	local spawned: any = stage.reports[1]
	if spawned.player ~= nil or spawned.kind ~= "stuck" or spawned.measurement ~= 0 then
		return false, `The buried NPC's spawn reported {spawned.kind} {spawned.measurement}, not stuck 0`
	end

	stage.Npcs.step(EXACT_TICK)

	local stepped: any = stage.reports[2]
	if #stage.reports ~= 2 or stepped.kind ~= "stuck" or stepped.player ~= nil then
		return false, `The buried NPC's step gave {#stage.reports - 1} more reports, not one stuck`
	elseif buried:getState().tick ~= EXACT_TICK then
		return false, "The buried NPC did not step"
	end

	return true, nil
end
