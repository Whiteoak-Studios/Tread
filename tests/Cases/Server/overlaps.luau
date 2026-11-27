--[[
    server:overlaps says whether a box, turned or not, overlaps a live
    character's hull, refusing what is no CFrame and size; server:addLadder
    registers a ladder and hands back the closure that removes it
--]]

--!strict
local roblox: any = require("@lune/roblox")

local Rig = require("../../Fixtures/Server/Rig")

local TICKS: number = 10
local TURN: number = math.rad(45) -- A door at an angle

return function (): (boolean, string | nil)
	local rig: Rig.Rig = Rig.new()
	local server: any = rig:start()
	server:create(rig.mock:addBot("Bot"), rig:at(0, 0))

	rig:tick(TICKS)

	local floor: number = rig.floor
	local size: any = roblox.Vector3.new(1, 4, 1)
	local over: any = roblox.CFrame.new(0, floor + 2, 0) * roblox.CFrame.Angles(0, TURN, 0)
	local away: any = roblox.CFrame.new(10, floor + 2, 0) * roblox.CFrame.Angles(0, TURN, 0)

	if not server:overlaps(over, size) then
		return false, "A turned box over the character's feet did not overlap its hull"
	elseif server:overlaps(away, size) then
		return false, "A box 10 studs from the character overlapped its hull"
	elseif pcall(server.overlaps, server, roblox.Vector3.zero, size) then
		return false, "overlaps took a Vector3 for the box's CFrame"
	end

	local remove: () -> () = server:addLadder(roblox.CFrame.new(-20, floor + 5, 10), roblox.Vector3.new(2, 10, 0.5))
	if type(remove) ~= "function" then
		return false, `addLadder handed back a {type(remove)}, not the closure that removes it`
	elseif pcall(server.addLadder, server, roblox.CFrame.new(-20, floor + 5, 10), roblox.Vector3.new(2, 10, 0.5)) then
		return false, "addLadder took a second ladder with the same box"
	end

	remove()

	-- Removed, the same box registers again
	local again: boolean =
		pcall(server.addLadder, server, roblox.CFrame.new(-20, floor + 5, 10), roblox.Vector3.new(2, 10, 0.5))
	if not again then
		return false, "A removed ladder's box did not register again"
	end

	return true, nil
end
