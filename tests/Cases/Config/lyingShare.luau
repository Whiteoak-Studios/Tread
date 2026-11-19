--[[
    The server's check takes antiEsp.lyingShare from 0 to antiEsp.slice and
    refuses it missing, not a number, below 0, not finite or above the
    slice, naming the key by its full path
--]]

--!strict
local Environment = require("../../Environment")

local CONFIG: string = "src/Config.luau"
local EXAMPLE: string = "tests/Fixtures/Config/Example.luau"
local PATH: string = "antiEsp.lyingShare"
local NUDGE: number = 1e-6 -- Seconds past an edge a value is moved

return function (): (boolean, string | nil)
	local Config = Environment.load(CONFIG)
	local Example = Environment.load(EXAMPLE)
	local slice: number = Example.server().antiEsp.slice

	local refused: { { value: any } } = {
		{ value = nil },
		{ value = "0.0005" },
		{ value = -NUDGE },
		{ value = 0 / 0 },
		{ value = math.huge },
		{ value = slice + NUDGE },
	}

	for _, refusal: { value: any } in refused do
		local server = Example.server()
		Example.set(server, PATH, refusal.value)

		local problem: string? = Example.refusal(Config.server, `server.{PATH}`, Example.shared(), server)
		if problem then
			return false, `At {refusal.value}: {problem}`
		end
	end

	-- A slice lowered below the share refuses the share, which the slice bounds
	local lowered = Example.server()
	Example.set(lowered, "antiEsp.slice", lowered.antiEsp.lyingShare - NUDGE)

	local problem: string? = Example.refusal(Config.server, `server.{PATH}`, Example.shared(), lowered)
	if problem then
		return false, `With the slice below it: {problem}`
	end

	for _, value: number in { 0, slice / 4, slice } do
		local server = Example.server()
		Example.set(server, PATH, value)

		local served: boolean, failure: any = pcall(Config.server, Example.shared(), server)
		if not served then
			return false, `Config.server refused {PATH} at {value}: {failure}`
		end
	end

	return true, nil
end
