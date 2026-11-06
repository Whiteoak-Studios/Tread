--[[
    Both entry points' checks refuse a time debt below one tick, which
    would leave the client's clock no tick to run, naming
    shared.ticks.debt, and take a debt of exactly one
--]]

--!strict
local Environment = require("../../Environment")

local CONFIG: string = "src/Config.luau"
local EXAMPLE: string = "tests/Fixtures/Config/Example.luau"

return function (): (boolean, string | nil)
	local Config = Environment.load(CONFIG)
	local Example = Environment.load(EXAMPLE)

	for _, debt: number in { 0, 0.5 } do
		local shared = Example.shared()
		Example.set(shared, "ticks.debt", debt)

		local problem: string? = Example.refusal(Config.server, "shared.ticks.debt", shared, Example.server())
			or Example.refusal(Config.client, "shared.ticks.debt", shared, Example.client())
		if problem then
			return false, `A debt of {debt}: {problem}`
		end
	end

	local shared = Example.shared()
	Example.set(shared, "ticks.debt", 1)

	local served: boolean, serverFailure: any = pcall(Config.server, shared, Example.server())
	local started: boolean, clientFailure: any = pcall(Config.client, shared, Example.client())
	if not served or not started then
		return false, `A debt of 1 was refused: {serverFailure or clientFailure}`
	end

	return true, nil
end
