--[[
    The server's check takes relay.clocks left out, true or false, beside
    workers or none, and refuses by its path a clocks that is neither true
    nor false
--]]

--!strict
local Environment = require("../../Environment")

local CONFIG: string = "src/Config.luau"
local EXAMPLE: string = "tests/Fixtures/Config/Example.luau"
local PATH: string = "server.relay.clocks"

-- Each relay table taken, by what it is
local TAKEN: { { label: string, relay: any } } = {
	{ label = "clocks left out", relay = { changes = true } },
	{ label = "clocks on", relay = { changes = true, clocks = true } },
	{ label = "clocks off", relay = { changes = true, clocks = false } },
	{ label = "clocks on with workers", relay = { workers = 2, timeout = 1, clocks = true } },
}

-- Each clocks refused
local REFUSED: { any } = { 1, 0, "true", {}, 0 / 0 }

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

	for _, clocks: any in REFUSED do
		local server = Example.server()
		server.relay = { changes = true, clocks = clocks }

		local problem: string? = Example.refusal(Config.server, PATH, Example.shared(), server)
		if problem then
			return false, `With relay.clocks {clocks}: {problem}`
		end
	end

	return true, nil
end
