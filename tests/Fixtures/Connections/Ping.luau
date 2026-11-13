--[[
    The engine's ping for Lune's players, set by a case for each player: it
    answers Player:GetNetworkPing, registered once for the whole run, since
    Lune refuses a method registered twice
--]]

--!strict
local roblox: any = require("@lune/roblox")

-- What GetNetworkPing reports for each player, in seconds
local Pings: { [any]: number } = {}

roblox.implementMethod("Player", "GetNetworkPing", function (player: any): number
	return Pings[player]
end)

return Pings
