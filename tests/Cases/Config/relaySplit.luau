--[[
    The server's check takes relay.split left out, true or false, beside
    workers or none, and refuses by its path a split that is neither true
    nor false
--]]

--!strict
local Environment = require("../../Environment")

local CONFIG: string = "src/Config.luau"
local EXAMPLE: string = "tests/Fixtures/Config/Example.luau"
local PATH: string = "server.relay.split"

-- Each relay table taken, by what it is
local TAKEN: { { label: string, relay: any } } = {
	{ label = "split left out", relay = { changes = true } },
	{ label = "split on", relay = { changes = true, split = true } },
	{ label = "split off", relay = { changes = true, split = false } },
	{ label = "split on with workers", relay = { workers = 2, timeout = 1, split = true } },
}

-- Each split refused
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

	for _, split: any in REFUSED do
		local server = Example.server()
		server.relay = { changes = true, split = split }

		local problem: string? = Example.refusal(Config.server, PATH, Example.shared(), server)
		if problem then
			return false, `With relay.split {split}: {problem}`
		end
	end

	return true, nil
end
