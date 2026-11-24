--[[
    The server's check takes antiEsp.workers at 0, at 2 and left out, and
    refuses by its path a negative count, a fraction, a string, NaN and an
    infinity
--]]

--!strict
local Environment = require("../../Environment")

local CONFIG: string = "src/Config.luau"
local EXAMPLE: string = "tests/Fixtures/Config/Example.luau"

-- Each workers taken, by what it is
local TAKEN: { { label: string, workers: number? } } = {
	{ label = "no workers", workers = 0 },
	{ label = "two workers", workers = 2 },
	{ label = "workers left out", workers = nil },
}

-- Each workers refused
local REFUSED: { any } = { -1, 1.5, "2", 0 / 0, math.huge }

return function (): (boolean, string | nil)
	local Config = Environment.load(CONFIG)
	local Example = Environment.load(EXAMPLE)

	for _, entry in TAKEN do
		local server = Example.server()
		server.antiEsp.workers = entry.workers

		local served: boolean, failure: any = pcall(Config.server, Example.shared(), server)
		if not served then
			return false, `Config.server refused {entry.label}: {failure}`
		end
	end

	for _, workers: any in REFUSED do
		local server = Example.server()
		server.antiEsp.workers = workers

		local problem: string? = Example.refusal(Config.server, "server.antiEsp.workers", Example.shared(), server)
		if problem then
			return false, `With antiEsp.workers {workers}: {problem}`
		end
	end

	return true, nil
end
