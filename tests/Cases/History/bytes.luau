--[[
    History.bytes gives the bytes every slot's ring holds together: none
    before a write, one ring of the history's length for each slot written,
    no more for a slot written again, and the same once a slot is cleared,
    since its ring is kept for its next life
--]]

--!strict
local Environment = require("../../Environment")

local HISTORY: string = "src/Server/History.luau"
local EXAMPLE: string = "tests/Fixtures/Config/Example.luau"
local STATE: string = "src/Step/State.luau"
local SAMPLE_BYTES: number = 24
local FIRST: number = 3 -- The slots written
local SECOND: number = 7

return function (): (boolean, string | nil)
	local History: any = Environment.load(HISTORY)
	local Example: any = Environment.load(EXAMPLE)
	local State: any = Environment.load(STATE)

	local shared: any = Example.shared()
	local server: any = Example.server()
	History.start(shared, server)

	local ring: number = (math.ceil(server.history.seconds * shared.rates.relay) + 1) * SAMPLE_BYTES
	local state: any = State.new()

	if History.bytes() ~= 0 then
		return false, `Before any write the history holds {History.bytes()} B`
	end

	History.write(FIRST, 1, state, 0)
	History.write(FIRST, 2, state, 0)
	if History.bytes() ~= ring then
		return false, `One slot written twice holds {History.bytes()} B, not one ring's {ring}`
	end

	History.write(SECOND, 2, state, 0)
	History.clear(FIRST)
	if History.bytes() ~= 2 * ring then
		return false, `Two slots, one cleared, hold {History.bytes()} B, not two rings' {2 * ring}`
	end

	return true, nil
end
