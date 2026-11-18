--[[
    The server's check takes relay.workers at 0, at 2 and left out, and
    refuses by its path a negative count, a fraction, a string, NaN and an
    infinity
--]]

--!strict
local Environment = require("../../Environment")

local CONFIG: string = "src/Config.luau"
local EXAMPLE: string = "tests/Fixtures/Config/Example.luau"

-- Each relay table taken, by what it is
local TAKEN: { { label: string, relay: any } } = {
	{ label = "no workers", relay = { changes = true, workers = 0 } },
	{ label = "two workers", relay = { changes = true, workers = 2, timeout = 1 } },
	{ label = "workers left out", relay = { changes = true } },
}

-- Each workers refused
local REFUSED: { any } = { -1, 1.5, "2", 0 / 0, math.huge }

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

	for _, workers: any in REFUSED do
		local server = Example.server()
		server.relay = { changes = true, workers = workers }

		local problem: string? = Example.refusal(Config.server, "server.relay.workers", Example.shared(), server)
		if problem then
			return false, `With relay.workers {workers}: {problem}`
		end
	end

	return true, nil
end
