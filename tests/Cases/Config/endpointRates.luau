--[[
    The server's check takes a rate for every endpoint the generated server
    module hears, keyed by its name with the first letter lowered, refuses
    the settings with any one of them missing, and takes no other
--]]

--!strict
local Environment = require("../../Environment")

local CONFIG: string = "src/Config.luau"
local EXAMPLE: string = "tests/Fixtures/Config/Example.luau"
local NETWORK: string = "src/Network/Server.luau"

-- The key a rate takes in the server settings, for an endpoint's name in the schema
local function rateKey(name: string): string
	return `{name:sub(1, 1):lower()}{name:sub(2)}`
end

return function (): (boolean, string | nil)
	local Config = Environment.load(CONFIG)
	local Example = Environment.load(EXAMPLE)
	local Network: any = Environment.load(NETWORK)

	-- The server hears an event it can listen to, and every function a client invokes
	local inbound: { string } = {}

	for name: string, endpoint: any in Network.events do
		if type(endpoint.on) == "function" then
			table.insert(inbound, name)
		end
	end

	for name: string in Network.functions do
		table.insert(inbound, name)
	end

	if #inbound == 0 then
		return false, "The server module hears no endpoint, so the case proves nothing"
	end

	local given: number = 0
	for _ in Example.server().rates do
		given += 1
	end

	if given ~= #inbound then
		return false, `The fixture gives {given} rates, where the server hears {#inbound} endpoints`
	end

	for _, name: string in inbound do
		local key: string = rateKey(name)
		local server = Example.server()

		if server.rates[key] == nil then
			return false, `The fixture gives no rate at server.rates.{key} for {name}, an endpoint the server hears`
		end

		server.rates[key] = nil

		local problem: string? = Example.refusal(Config.server, `server.rates.{key}`, Example.shared(), server)
		if problem then
			return false, problem
		end
	end

	return true, nil
end
