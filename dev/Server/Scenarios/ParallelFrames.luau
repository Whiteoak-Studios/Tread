--[[
    Where in a frame results handed to Actors at PreSimulation or
    PostSimulation are first all readable on the main thread, a line an arm
    with nothing judged and no bots loading the server
--]]

--!strict
local ServerScriptService = game:GetService("ServerScriptService")

local Frames = require(ServerScriptService.Server.Parallel.Frames)

local SEPARATOR: string = "; " -- Between the problems

return function (): (boolean, string | nil)
	local lines: { string }, problems: { string } = Frames.run()

	for _, line: string in lines do
		print(line)
	end

	if #problems > 0 then
		return false, table.concat(problems, SEPARATOR)
	end

	return true, nil
end
