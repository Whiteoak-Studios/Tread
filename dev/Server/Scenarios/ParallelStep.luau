--[[
    Whether the step's casts, its overlap probe, native code and the dev
    shared table behave on Actor workers as on the main thread, a line a
    probe a clone, passing only when all four probes pass
--]]

--!strict
local ServerScriptService = game:GetService("ServerScriptService")

local Step = require(ServerScriptService.Server.Parallel.Step)

local SEPARATOR: string = "; " -- Between the problems

return function (): (boolean, string | nil)
	local lines: { string }, problems: { string } = Step.run()

	for _, line: string in lines do
		print(line)
	end

	if #problems > 0 then
		return false, table.concat(problems, SEPARATOR)
	end

	return true, nil
end
