--[[
    character:setOutfit sets the look a viewer sent the character holds,
    refusing a value outside its declaration; character:setInvisible sends
    the character to no other player while on and sends it again once off
--]]

--!strict
local Rig = require("../../Fixtures/Server/Rig")

local TICKS: number = 3
local HEAD: number = 12 -- An item index the example's head slot holds

return function (): (boolean, string | nil)
	local rig: Rig.Rig = Rig.new()
	local server: any = rig:start()
	local Keyframe: any = rig:require(rig.tread.Codec.Keyframe)
	local Relay: any = rig:require(rig.tread.Server.Relay)

	local watcherBot: any = rig.mock:addBot("Watcher")
	server:create(watcherBot, rig:at(0, 0))
	local dressed: any = server:create(rig.mock:addBot("Dressed"), rig:at(6, 0))

	dressed:setOutfit({ head = HEAD })
	rig:tick(TICKS)

	local keyframe: any = Keyframe.read(server:keyframe(watcherBot))
	local seen: any = keyframe.characters[1]
	if #keyframe.characters ~= 1 or buffer.len(seen.look) == 0 then
		return false, "The watcher's keyframe holds no look for the dressed character beside it"
	elseif pcall(dressed.setOutfit, dressed, { head = -1 }) then
		return false, "setOutfit took a head outside its declaration"
	elseif pcall(dressed.setOutfit, dressed, HEAD) then
		return false, "setOutfit took a number for the look"
	end

	dressed:setInvisible(true)
	rig:tick(TICKS)

	if Relay.isSent(watcherBot, dressed._slot) then
		return false, "An invisible character was still sent to the watcher"
	end

	dressed:setInvisible(false)
	rig:tick(TICKS)

	if not Relay.isSent(watcherBot, dressed._slot) then
		return false, "Visible again, the character was not sent to the watcher"
	elseif pcall(dressed.setInvisible, dressed, "on") then
		return false, "setInvisible took a string"
	end

	return true, nil
end
