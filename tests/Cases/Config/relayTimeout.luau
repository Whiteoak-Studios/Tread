--[[
    The server's check takes relay.timeout with workers and with none, and
    refuses by its path workers above 0 with no timeout, and a timeout of 0,
    below 0, a string, NaN or an infinity
--]]

--!strict
local Environment = require("../../Environment")

local CONFIG: string = "src/Config.luau"
local EXAMPLE: string = "tests/Fixtures/Config/Example.luau"
local PATH: string = "server.relay.timeout"

-- Each relay table taken, by what it is
local TAKEN: { { label: string, relay: any } } = {
	{ label = "two workers with a timeout", relay = { workers = 2, timeout = 1 } },
	{ label = "a short timeout", relay = { workers = 1, timeout = 0.001 } },
	{ label = "a timeout with no workers", relay = { workers = 0, timeout = 1 } },
	{ label = "a timeout with workers left out", relay = { changes = true, timeout = 1 } },
	{ label = "no workers and no timeout", relay = { workers = 0 } },
}

-- Each timeout refused, beside two workers
local REFUSED: { any } = { 0, -1, "1", 0 / 0, math.huge }

return function (): (boolean, string | nil)
	local Config = Environment.load(CONFIG)
	local Example = Environment.load(EXAMPLE)

	for _, entry in TAKEN do
		local server = Example.server()
		server.relay = entry.relay

		local served: boolean, failure: any = pcall(Config.server, Example.shared(), server)
		if not served then
			return false, `Config.server refused {entry.label}: {failure}`
		end
	end

	local missing = Example.server()
	missing.relay = { changes = true, workers = 2 }

	local problem: string? = Example.refusal(Config.server, PATH, Example.shared(), missing)
	if problem then
		return false, `With two workers and no timeout: {problem}`
	end

	local _, failure: any = pcall(Config.server, Example.shared(), missing)
	if not string.find(tostring(failure), "server.relay.workers is 2", 1, true) then
		return false, `The refusal of two workers with no timeout named no workers: {failure}`
	end

	for _, timeout: any in REFUSED do
		local server = Example.server()
		server.relay = { workers = 2, timeout = timeout }

		problem = Example.refusal(Config.server, PATH, Example.shared(), server)
		if problem then
			return false, `With relay.timeout {timeout}: {problem}`
		end
	end

	return true, nil
end
