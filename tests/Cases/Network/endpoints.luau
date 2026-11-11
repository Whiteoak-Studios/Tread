--[[
    Volt's server and client modules for Tread.volt start over the mock and
    expose the twelve endpoints the design names and no other, each with
    the calls its side makes
--]]

--!strict
local Environment = require("../../Environment")

local SERVER: string = "src/Network/Server.luau"
local CLIENT: string = "src/Network/Client.luau"

-- The endpoints a client sends, in the design's order
local HEARD: { string } = { "Move", "View" }

-- The endpoints the server sends, in the design's order
local SENT: { string } =
	{ "Relay", "Withheld", "Owner", "Feed", "Slots", "Death", "Platform", "Gravity", "Spectate", "Shared" }

local FIRES: { string } = { "fire", "fireAll", "fireList", "fireExcept", "fireSet" } -- What the server sends with
local LISTENS: { string } = { "on", "iter" } -- What the side that hears an event takes it with
local CLIENT_FIRES: { string } = { "fire" }

-- Names the first call an endpoint lacks, or nil when it has every one
local function lacking(network: any, name: string, calls: { string }): string?
	local endpoint: any = network[name]
	if type(endpoint) ~= "table" then
		return `{name} is a {type(endpoint)}, not an endpoint`
	end

	for _, call: string in calls do
		if type(endpoint[call]) ~= "function" then
			return `{name}.{call} is a {type(endpoint[call])}, not a function`
		end
	end

	return nil
end

-- Names the first event a module lists that the design does not, or says how many it lists when that is wrong
local function unlisted(network: any, side: string): string?
	local count: number = 0

	for name: string in network.events do
		if table.find(HEARD, name) == nil and table.find(SENT, name) == nil then
			return `The {side} module lists {name}, an endpoint the design does not name`
		end

		count += 1
	end

	if count ~= #SENT + #HEARD then
		return `The {side} module lists {count} endpoints, where the design names {#SENT + #HEARD}`
	end

	return nil
end

return function (): (boolean, string | nil)
	local server: any = Environment.load(SERVER)
	local client: any = Environment.load(CLIENT)
	local problem: string?

	for _, name: string in HEARD do
		problem = lacking(server, name, LISTENS) or lacking(client, name, CLIENT_FIRES)
		if problem then
			return false, problem
		end
	end

	for _, name: string in SENT do
		problem = lacking(server, name, FIRES) or lacking(client, name, LISTENS)
		if problem then
			return false, problem
		end
	end

	problem = unlisted(server, "server") or unlisted(client, "client")
	if problem then
		return false, problem
	end

	return true, nil
end
