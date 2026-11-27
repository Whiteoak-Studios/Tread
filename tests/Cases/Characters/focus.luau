--[[
    Each Player gets one anchored focus part under the server-only Camera,
    as their ReplicationFocus, placed at their body and moved there at about
    5 Hz, staggered across relay ticks, to the spectated target's body while
    they spectate; a bot gets none, and a leave takes the part away
--]]

--!strict
local roblox: any = require("@lune/roblox")

local Pings = require("../../Fixtures/Connections/Ping")
local Rig = require("../../Fixtures/Server/Rig")

local PING: number = 0.05 -- Seconds each Lune player's engine ping reports
local GROUPS: number = 4 -- Relay ticks a full pass takes, the example's 20 Hz relay over a 5 Hz move
local CLOSE: number = 0.1 -- Studs a part may sit from the body it follows

-- Whether a part sits at a point
local function at(part: any, point: any): boolean
	return (part.Position - point).Magnitude <= CLOSE
end

-- The relay ticks after which a part first sits at a point, from the tick after now, nil within the ticks given
local function arrives(rig: Rig.Rig, part: any, point: any, ticks: number): number?
	for tick: number = 1, ticks do
		rig:tick(1)

		if at(part, point) then
			return tick
		end
	end

	return nil
end

return function (): (boolean, string | nil)
	local rig: Rig.Rig = Rig.new(function (_: any, settings: any)
		-- With no hook, and Lune's Workspace not streaming, a Player's teleport is ready at once
		settings.prestream = nil
	end)

	local server: any = rig:start()
	local Characters: any = rig:require(rig.tread.Server.Characters)
	local workspace: any = rig.globals.game:GetService("Workspace")

	local first: any = roblox.Instance.new("Player")
	local second: any = roblox.Instance.new("Player")
	Pings[first] = PING
	Pings[second] = PING

	local firstCharacter: any = server:create(first, rig:at(0, 0))
	local secondCharacter: any = server:create(second, rig:at(6, 0))
	server:create(rig.mock:addBot("Bot"), rig:at(-6, 0))

	local holder: any = workspace:FindFirstChild("TreadFocus")
	if not holder or not holder:IsA("Camera") or #holder:GetChildren() ~= 2 then
		return false, `The focus Camera holds {holder and #holder:GetChildren()} parts, not one for each Player`
	end

	local firstPart: any = first.ReplicationFocus
	local secondPart: any = second.ReplicationFocus
	if not firstPart or firstPart.Parent ~= holder or not firstPart.Anchored or secondPart.Parent ~= holder then
		return false, "A Player's ReplicationFocus is no anchored part under the focus Camera"
	elseif (firstPart.Position - firstCharacter:getState().root).Magnitude > CLOSE then
		return false, "A focus part was not placed at its body"
	end

	-- After a move, each part follows within a full pass, the two on different relay ticks
	-- On the floor, so neither body moves again once set down
	firstCharacter:teleport(roblox.CFrame.new(-12, rig.floor, 8))
	secondCharacter:teleport(roblox.CFrame.new(-4, rig.floor, 16))
	rig:tick(1)

	local firstAt: number? = nil
	local secondAt: number? = nil
	for tick: number = 1, GROUPS do
		rig:tick(1)

		if not firstAt and at(firstPart, firstCharacter:getState().root) then
			firstAt = tick
		end

		if not secondAt and at(secondPart, secondCharacter:getState().root) then
			secondAt = tick
		end
	end

	if not firstAt or not secondAt then
		return false, `The focus parts followed their bodies after {firstAt} and {secondAt} of {GROUPS} relay ticks`
	elseif firstAt == secondAt then
		return false, "Both focus parts moved on the same relay tick"
	end

	-- While spectating, a part follows the target's body
	server:spectate(second, firstCharacter)
	if not arrives(rig, secondPart, firstCharacter:getState().root, GROUPS) then
		return false, "The spectating player's focus part did not follow the target's body"
	end

	server:spectate(second, nil)

	-- A leave takes the part away
	Characters.leave(first)
	if firstPart.Parent ~= nil or #holder:GetChildren() ~= 1 then
		return false, "The player who left kept their focus part"
	end

	return true, nil
end
