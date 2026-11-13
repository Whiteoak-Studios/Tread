--[[
    Server.start refuses tables Config refuses, naming the first wrong key,
    before it starts anything, so a start with good tables still runs after
    it; and it runs once, refusing a second start
--]]

--!strict
local Rig = require("../../Fixtures/Server/Rig")

local MISSING: string = "server.rates.move" -- The one inbound endpoint's rate, which a bad table leaves out

return function (): (boolean, string | nil)
	local rig: Rig.Rig = Rig.new()
	local rate: any = rig.settings.rates.move
	rig.settings.rates.move = nil

	local refused: boolean, message: any = pcall(rig.Server.start, rig.shared, rig.settings)
	if refused then
		return false, "Server.start took server settings that give Move no rate"
	elseif not string.find(tostring(message), MISSING, 1, true) then
		return false, `Server.start's refusal of the missing rate named something else: {message}`
	end

	rig.settings.rates.move = rate
	local started: boolean, failure: any = pcall(rig.start, rig)
	if not started then
		return false, `A good start after a refused one failed: {failure}`
	end

	local again: boolean = pcall(rig.Server.start, rig.shared, rig.settings)
	if again then
		return false, "Server.start ran a second time"
	end

	return true, nil
end
