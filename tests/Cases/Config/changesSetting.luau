--[[
    The server's check takes relay.changes left out, true or false, and an
    empty relay table, and refuses by its path a relay that isn't a table,
    a key Tread doesn't read, and a changes that is neither true nor false
--]]

--!strict
local Environment = require("../../Environment")

local CONFIG: string = "src/Config.luau"
local EXAMPLE: string = "tests/Fixtures/Config/Example.luau"

-- Each relay table taken, by what it is
local TAKEN: { { label: string, relay: any } } = {
	{ label = "no relay table", relay = nil },
	{ label = "an empty relay table", relay = {} },
	{ label = "changes on", relay = { changes = true } },
	{ label = "changes off", relay = { changes = false } },
}

-- Each refused, with the path its refusal names
local REFUSED: { { path: string, relay: any } } = {
	{ path = "relay", relay = true },
	{ path = "relay", relay = 1 },
	{ path = "relay.changes", relay = { changes = 1 } },
	{ path = "relay.changes", relay = { changes = "true" } },
	{ path = "relay.changes", relay = { changes = {} } },
	{ path = "relay.delta", relay = { changes = true, delta = true } },
}

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

	for _, entry in REFUSED do
		local server = Example.server()
		server.relay = entry.relay

		local problem: string? = Example.refusal(Config.server, `server.{entry.path}`, Example.shared(), server)
		if problem then
			return false, `With relay {entry.path} wrong: {problem}`
		end
	end

	return true, nil
end
