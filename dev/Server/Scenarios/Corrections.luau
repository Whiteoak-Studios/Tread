--[[
    Prints the correction telemetry for each player in the server, their
    small and large corrections and the minutes those cover, and fails when
    no player is counted or one is not
--]]

--!strict
local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")

local Corrections = require(ServerScriptService.Server.Corrections)

local SEPARATOR: string = ", " -- Between the names of the players not counted

return function (): (boolean, string | nil)
	local missing: { string } = {}
	local counted: number = 0

	for _, player: Player in Players:GetPlayers() do
		local counts: Corrections.Counts? = Corrections.get(player)
		if counts then
			counted += 1

			local minutes: string = string.format("%.2f", counts.minutes)
			print(`Corrections {player.Name}: {counts.small} small and {counts.large} large over {minutes} minutes`)
		else
			table.insert(missing, player.Name)
		end
	end

	if #missing > 0 then
		return false, `no character has been built yet for {table.concat(missing, SEPARATOR)}, so none is counted`
	elseif counted == 0 then
		return false, "no player is in the server to count"
	end

	return true, nil
end
