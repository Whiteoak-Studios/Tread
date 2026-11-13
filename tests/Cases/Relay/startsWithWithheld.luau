--[[
    The relay refuses to start on the example's tables without a
    sendWithheld that is a function, the withheld block's send beside the
    relay block's, and starts once it has one
--]]

--!strict
local Environment = require("../../Environment")

local RELAY: string = "src/Server/Relay.luau"
local EXAMPLE: string = "tests/Fixtures/Config/Example.luau"
local FIELDS: string = "src/Codec/Fields.luau"
local NOT_FUNCTIONS: { any } = { "send", 1, {}, false }

return function (): (boolean, string | nil)
	local Relay: any = Environment.load(RELAY)
	local Example: any = Environment.load(EXAMPLE)
	local Fields: any = Environment.load(FIELDS)

	local shared: any = Example.shared()
	local settings: any = { shared = shared, server = Example.server(), layout = Fields.compile(shared.fields) }
	local function nothing() end

	for _, value: any in NOT_FUNCTIONS do
		if pcall(Relay.start, settings, nothing, value, nothing, nothing) then
			return false, `Relay.start took a {typeof(value)} as sendWithheld`
		end
	end

	if pcall(Relay.start, settings, nothing, nil, nothing, nothing) then
		return false, "Relay.start started with no sendWithheld"
	elseif pcall(Relay.run, 1, {}, {}, {}) then
		return false, "A refused start left the relay running"
	elseif not pcall(Relay.start, settings, nothing, nothing, nothing, nothing) then
		return false, "Relay.start refused the example's tables with all four of its functions"
	elseif not pcall(Relay.run, 1, {}, {}, {}) then
		return false, "The relay did not run once it had started"
	end

	return true, nil
end
