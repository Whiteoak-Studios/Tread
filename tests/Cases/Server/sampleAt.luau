--[[
    server:sampleAt reads a character's history at a render time, crossed
    onto Vector3 with its hit shapes placed at its feet, the same table on
    each read of the slot's posture; it answers nil for a time the history
    no longer holds and for a destroyed target, and refuses what is no target
--]]

--!strict
local Rig = require("../../Fixtures/Server/Rig")

local TICKS: number = 30 -- Past the history's 21 relay ticks, so its oldest have gone
local TOLERANCE: number = 1 / 32 -- Studs, the history's height step

return function (): (boolean, string | nil)
	local rig: Rig.Rig = Rig.new()
	local server: any = rig:start()
	local character: any = server:create(rig.mock:addBot("Bot"), rig:at(0, 0))

	rig:tick(TICKS)

	local state: any = character:getState()
	local sample: any = server:sampleAt(character, TICKS)
	if not sample then
		return false, "The newest relay tick's sample was missing"
	elseif typeof(sample.position) ~= "Vector3" or typeof(sample.body.from) ~= "Vector3" then
		return false, `The sample holds a {typeof(sample.position)} position and {typeof(sample.body.from)} shapes`
	elseif (sample.position - state.root).Magnitude > TOLERANCE or sample.posture ~= "Stand" then
		return false,
			`The sample stands at {sample.position} in {sample.posture}, where the character stands at {state.root}`
	end

	-- The example's standing body capsule runs from 1 to 4 studs above the feet
	if math.abs(sample.body.from.Y - (sample.position.Y + 1)) > TOLERANCE or not sample.zones.head then
		return false, `The body capsule starts at {sample.body.from}, not a stud over the feet at {sample.position}`
	end

	if server:sampleAt(character, TICKS - 1) ~= sample then
		return false, "A second read of the same posture gave a new table"
	elseif server:sampleAt(character, 1) ~= nil then
		return false, "A render time the history no longer holds gave a sample"
	elseif pcall(server.sampleAt, server, {}, TICKS) then
		return false, "sampleAt took a table that is no character or NPC"
	elseif pcall(server.sampleAt, server, character, TICKS, "late") then
		return false, "sampleAt took a string for the command time"
	end

	character:destroy()
	if server:sampleAt(character, TICKS) ~= nil then
		return false, "A destroyed character still answered from the history"
	end

	return true, nil
end
