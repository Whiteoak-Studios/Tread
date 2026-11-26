--[[
    The server's check takes relay.past on with changes, and off or left out
    with or without them, and refuses by its path past on with changes off
    or left out, and a past that is no boolean
--]]

--!strict
local Environment = require("../../Environment")

local CONFIG: string = "src/Config.luau"
local EXAMPLE: string = "tests/Fixtures/Config/Example.luau"
local CHANGES: string = "server.relay.changes"
local PAST: string = "server.relay.past"

-- Each relay table taken, by what it is
local TAKEN: { { label: string, relay: any } } = {
	{ label = "past with changes", relay = { changes = true, past = true } },
	{ label = "past with changes and workers", relay = { changes = true, past = true, workers = 2, timeout = 1 } },
	{ label = "past off with changes", relay = { changes = true, past = false } },
	{ label = "past off without changes", relay = { past = false } },
	{ label = "past left out without changes", relay = {} },
}

-- Each relay table refused for its changes, past on beside them
local NO_CHANGES: { { label: string, relay: any } } = {
	{ label = "changes left out", relay = { past = true } },
	{ label = "changes off", relay = { changes = false, past = true } },
}

-- Each past refused for what it is
local REFUSED: { any } = { 1, "true", 0 / 0 }

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

	for _, entry in NO_CHANGES do
		local server = Example.server()
		server.relay = entry.relay

		local problem: string? = Example.refusal(Config.server, CHANGES, Example.shared(), server)
		if problem then
			return false, `With {entry.label}: {problem}`
		end

		local _, failure: any = pcall(Config.server, Example.shared(), server)
		if not string.find(tostring(failure), "since server.relay.past is true", 1, true) then
			return false, `The refusal with {entry.label} named no past: {failure}`
		end
	end

	for _, past: any in REFUSED do
		local server = Example.server()
		server.relay = { changes = true, past = past }

		local problem: string? = Example.refusal(Config.server, PAST, Example.shared(), server)
		if problem then
			return false, `With relay.past {past}: {problem}`
		end
	end

	return true, nil
end
