--[[
    A ragdoll joint's twist is refused when its lower limit is above its
    upper, naming the upper, and when either is missing, and a twist range
    of one angle or wholly below 0 is accepted
--]]

--!strict
local Environment = require("../../Environment")

local CONFIG: string = "src/Config.luau"
local EXAMPLE: string = "tests/Fixtures/Config/Example.luau"
local JOINT: string = "bodies.jointLimits.Neck"

type Limit = { tilt: number, twistLower: number?, twistUpper: number?, twist: number? }
type Refusal = { limit: Limit, path: string }

return function (): (boolean, string | nil)
	local Config = Environment.load(CONFIG)
	local Example = Environment.load(EXAMPLE)

	local refusals: { Refusal } = {
		{ limit = { tilt = 30, twistLower = 10, twistUpper = -10 }, path = `{JOINT}.twistUpper` },
		{ limit = { tilt = 30, twistLower = -5, twistUpper = -5.5 }, path = `{JOINT}.twistUpper` },
		{ limit = { tilt = 30, twistUpper = 40 }, path = `{JOINT}.twistLower` },
		{ limit = { tilt = 30, twist = 40 }, path = `{JOINT}.twistLower` },
	}

	for _, refusal: Refusal in refusals do
		local client = Example.client()
		Example.set(client, JOINT, refusal.limit)

		local problem: string? = Example.refusal(Config.client, `client.{refusal.path}`, Example.shared(), client)
		if problem then
			return false, problem
		end
	end

	local accepted: { Limit } = {
		{ tilt = 0, twistLower = 15, twistUpper = 15 },
		{ tilt = 5, twistLower = -120, twistUpper = -5 },
	}

	for _, limit: Limit in accepted do
		local client = Example.client()
		Example.set(client, JOINT, limit)

		local passed: boolean, failure: any = pcall(Config.client, Example.shared(), client)
		if not passed then
			return false, `A twist from {limit.twistLower} to {limit.twistUpper} was refused: {failure}`
		end
	end

	return true, nil
end
