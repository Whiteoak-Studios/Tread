--[[
    The server's check refuses settings missing rates.view, antiEsp.nearRadius
    or antiEsp.nearRate, naming each, refuses 0, negatives, NaN and both
    infinities in the two anti-ESP keys, and takes them above 0
--]]

--!strict
local Environment = require("../../Environment")

local CONFIG: string = "src/Config.luau"
local EXAMPLE: string = "tests/Fixtures/Config/Example.luau"

local REQUIRED: { string } = { "rates.view", "antiEsp.nearRadius", "antiEsp.nearRate" }
local KEYS: { string } = { "antiEsp.nearRadius", "antiEsp.nearRate" } -- The two above 0
local REFUSED: { number } = { 0, -1, -250, 0 / 0, math.huge, -math.huge }
local TAKEN: { number } = { 1 / 512, 250, 30, 1000 }

return function (): (boolean, string | nil)
	local Config = Environment.load(CONFIG)
	local Example = Environment.load(EXAMPLE)

	for _, path: string in REQUIRED do
		local server = Example.server()
		Example.set(server, path, nil)

		local problem: string? = Example.refusal(Config.server, `server.{path}`, Example.shared(), server)
		if problem then
			return false, `With {path} missing: {problem}`
		end
	end

	for _, path: string in KEYS do
		for _, value: number in REFUSED do
			local server = Example.server()
			Example.set(server, path, value)

			local problem: string? = Example.refusal(Config.server, `server.{path}`, Example.shared(), server)
			if problem then
				return false, `With {path} at {value}: {problem}`
			end
		end

		for _, value: number in TAKEN do
			local server = Example.server()
			Example.set(server, path, value)

			local served: boolean, failure: any = pcall(Config.server, Example.shared(), server)
			if not served then
				return false, `Config.server refused {path} at {value}: {failure}`
			end
		end
	end

	return true, nil
end
