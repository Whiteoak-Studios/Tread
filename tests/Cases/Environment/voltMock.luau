--[[
    A generated module's require of ReplicatedStorage.Packages.Volt starts
    its runtime over the environment's mock, which Lune's missing remotes
    would refuse, as the server or as a player the mock joins
--]]

--!strict
local Volt = require("@volt")

local Environment = require("../../Environment")

local GLOBALS: string = "tests/Fixtures/Environment/Globals.luau"
local PLAYER: string = "Player" -- Whom a client runtime joins the mock as

-- The options Volt 0.1.0 writes into a schema table by default
local OPTIONS: { [string]: any } = {
	flush = 1,
	manualReplication = false,
	maxOutgoing = 262144,
	maxPacket = 8192,
	maxPacketsPerSecond = 240,
	unreliableBudget = 900,
	writeValidation = true,
}

-- The least schema table a generated module hands start: one side, no messages
local function schema(side: string): Volt.Schema
	return {
		version = Volt.version,
		hash = 0,
		scope = "Environment",
		side = side,
		idBytes = 1,
		options = OPTIONS,
		messages = {},
		outgoing = {},
	}
end

return function (): (boolean, string | nil)
	-- Without a transport, start opens the real remotes, which Lune lacks
	local opened: boolean = pcall(Volt.start, schema("server"))
	if opened then
		return false, "Volt.start ran without a transport under Lune, so the stand-in's success proves nothing"
	end

	local globals: any = Environment.load(GLOBALS)
	local volt: any = globals.require(globals.game:GetService("ReplicatedStorage").Packages.Volt)

	local served: boolean, server: any = pcall(volt.start, schema("server"))
	if not served or server == nil then
		return false, `The stand-in refused a server schema: {server}`
	end

	if #volt.mock.players ~= 0 then
		return false, "Starting the server joined a player to the mock"
	end

	local connected: boolean, client: any = pcall(volt.start, schema("client"))
	if not connected or client == nil then
		return false, `The stand-in refused a client schema: {client}`
	end

	if #volt.mock.players ~= 1 or volt.mock.players[1].Name ~= PLAYER then
		return false, `The client runtime did not join the mock as {PLAYER}`
	end

	-- The client's handshake crosses on a step, which errors if either runtime is not on the mock
	volt.mock:step()
	volt.mock:step()

	return true, nil
end
