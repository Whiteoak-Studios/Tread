--[[
    character:setMode runs the exact depenetration when the mode comes back
    to Walk, so a body still buried is reported stuck again, and only then;
    Parked sends the body to no other player and leaves its ticks out of the
    history; a mode Tread has no name for is refused
--]]

--!strict
local roblox: any = require("@lune/roblox")

local Rig = require("../../Fixtures/Server/Rig")

local TICKS: number = 3
local BURY: number = 1 -- Studs above the floor inside the vault a character is built at

return function (): (boolean, string | nil)
	local rig: Rig.Rig = Rig.new()
	local server: any = rig:start()
	local Relay: any = rig:require(rig.tread.Server.Relay)

	local buriedBot: any = rig.mock:addBot("Buried")
	local buried: any = server:create(buriedBot, roblox.CFrame.new(rig.vault.x, rig.floor + BURY, rig.vault.z))
	if #rig:reportedFor("stuck", buriedBot) ~= 1 then
		return false, "A character built inside the vault was not reported stuck at its spawn"
	end

	buried:setMode("Noclip")
	buried:setMode("Parked")
	if #rig:reportedFor("stuck", buriedBot) ~= 1 then
		return false, "Leaving Walk ran the exact depenetration"
	end

	buried:setMode("Walk")
	if #rig:reportedFor("stuck", buriedBot) ~= 2 then
		return false, "Coming back to Walk did not run the exact depenetration that finds the body still buried"
	end

	buried:destroy()

	-- A watcher beside a walker, then the walker parked
	local watcherBot: any = rig.mock:addBot("Watcher")
	server:create(watcherBot, rig:at(0, 0))
	local walker: any = server:create(rig.mock:addBot("Walker"), rig:at(6, 0))
	rig:tick(TICKS)

	if not Relay.isSent(watcherBot, walker._slot) then
		return false, "The watcher was never sent the walker beside it"
	end

	walker:setMode("Parked")
	rig:tick(TICKS)

	local parkedAt: number = TICKS * 2
	if Relay.isSent(watcherBot, walker._slot) then
		return false, "A parked character was still sent to the watcher"
	elseif server:sampleAt(walker, parkedAt) ~= nil then
		return false, "A tick spent parked answered a hit test"
	elseif walker:getState().moveMode ~= "Parked" then
		return false, `The parked character's state reads {walker:getState().moveMode}`
	end

	walker:setMode("Walk")
	rig:tick(TICKS)

	if not Relay.isSent(watcherBot, walker._slot) then
		return false, "Back in Walk the character was not sent to the watcher again"
	elseif pcall(walker.setMode, walker, "Fly") then
		return false, "setMode took a mode Tread has no name for"
	end

	return true, nil
end
