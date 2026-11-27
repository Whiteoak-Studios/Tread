--[[
    The client's check requires the per-frame look as a function: client
    settings with none, or with a look that is a number, are refused naming
    client.look, and the example's own look passes
--]]

--!strict
local Environment = require("../../Environment")

local CONFIG: string = "src/Config.luau"
local EXAMPLE: string = "tests/Fixtures/Config/Example.luau"

return function (): (boolean, string | nil)
	local Config = Environment.load(CONFIG)
	local Example = Environment.load(EXAMPLE)

	-- Each row a table of its own, since a nil in a list's literal is never iterated
	local rows: { { value: any } } = { { value = nil }, { value = 5 }, { value = "look" } }

	for _, row: { value: any } in rows do
		local client = Example.client()
		Example.set(client, "look", row.value)

		local problem: string? = Example.refusal(Config.client, "client.look", Example.shared(), client)
		if problem then
			return false, problem
		end
	end

	local started: boolean, failure: any = pcall(Config.client, Example.shared(), Example.client())
	if not started then
		return false, `Config.client refused client settings with a look function: {failure}`
	end

	return true, nil
end
