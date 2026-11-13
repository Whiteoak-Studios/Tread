--[[
    Both entry points' checks refuse a mantle time that rounds to no tick
    or to more than 255 at the simulation rate, naming
    shared.step.mantleTime, and take one that rounds inside, at two rates
--]]

--!strict
local Environment = require("../../Environment")

local CONFIG: string = "src/Config.luau"
local EXAMPLE: string = "tests/Fixtures/Config/Example.luau"
local PATH: string = "shared.step.mantleTime"

-- A simulation rate in Hz, a mantle time in seconds, and whether the ticks it rounds to are refused
type Edge = { rate: number, seconds: number, refused: boolean }

local EDGES: { Edge } = {
	{ rate = 20, seconds = 0.02, refused = true }, -- 0.4 ticks, which round to none
	{ rate = 20, seconds = 0.03, refused = false }, -- 0.6, which round to 1
	{ rate = 20, seconds = 0.05, refused = false }, -- 1
	{ rate = 20, seconds = 0.5, refused = false }, -- Frontier Zero's 10
	{ rate = 20, seconds = 12.75, refused = false }, -- 255
	{ rate = 20, seconds = 12.77, refused = false }, -- 255.4, which round to 255
	{ rate = 20, seconds = 12.78, refused = true }, -- 255.6, which round to 256
	{ rate = 20, seconds = 13, refused = true }, -- 260
	{ rate = 30, seconds = 0.01, refused = true }, -- 0.3
	{ rate = 30, seconds = 8.5, refused = false }, -- 255
	{ rate = 30, seconds = 8.52, refused = true }, -- 255.6
}

return function (): (boolean, string | nil)
	local Config = Environment.load(CONFIG)
	local Example = Environment.load(EXAMPLE)

	for _, edge: Edge in EDGES do
		local shared = Example.shared()
		shared.rates.simulation = edge.rate
		shared.step.mantleTime = edge.seconds

		local at: string = `{edge.seconds} s at {edge.rate} Hz`

		if edge.refused then
			local problem: string? = Example.refusal(Config.server, PATH, shared, Example.server())
				or Example.refusal(Config.client, PATH, shared, Example.client())
			if problem then
				return false, `A mantle time of {at}: {problem}`
			end
		else
			local served: boolean, serverFailure: any = pcall(Config.server, shared, Example.server())
			local started: boolean, clientFailure: any = pcall(Config.client, shared, Example.client())
			if not served or not started then
				return false, `A mantle time of {at} was refused: {serverFailure or clientFailure}`
			end
		end
	end

	return true, nil
end
