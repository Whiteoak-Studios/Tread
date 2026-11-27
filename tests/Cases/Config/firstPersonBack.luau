--[[
    The client's check takes a first-person back of 0 or more studs, and
    refuses the block or its back missing, a negative back and a back that
    is no number, each refusal naming the key
--]]

--!strict
local Environment = require("../../Environment")

local CONFIG: string = "src/Config.luau"
local EXAMPLE: string = "tests/Fixtures/Config/Example.luau"

type Refusal = { path: string, value: any }

return function (): (boolean, string | nil)
	local Config = Environment.load(CONFIG)
	local Example = Environment.load(EXAMPLE)

	local refusals: { Refusal } = {
		{ path = "firstPerson", value = nil },
		{ path = "firstPerson", value = 1 },
		{ path = "firstPerson.back", value = nil },
		{ path = "firstPerson.back", value = -0.5 },
		{ path = "firstPerson.back", value = "1" },
		{ path = "firstPerson.back", value = 0 / 0 },
		{ path = "firstPerson.back", value = math.huge },
	}

	for _, refusal: Refusal in refusals do
		local client = Example.client()
		Example.set(client, refusal.path, refusal.value)

		local problem: string? = Example.refusal(Config.client, `client.{refusal.path}`, Example.shared(), client)
		if problem then
			return false, problem
		end
	end

	-- A back of 0 draws the copy where the world rig stands, which a game may choose
	local client = Example.client()
	client.firstPerson.back = 0

	local passed: boolean, failure: any = pcall(Config.client, Example.shared(), client)
	if not passed then
		return false, `Config.client refused a back of 0: {failure}`
	end

	return true, nil
end
