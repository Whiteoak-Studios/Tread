--[[
    The client's check takes perFrame's caps and pool.spare as whole numbers
    from 1, each optional, perFrame given empty or left out with pool, and
    refuses 0, a fraction, a negative, a non-number, NaN, an infinity and a
    key Tread doesn't read, each refusal naming the key
--]]

--!strict
local Environment = require("../../Environment")

local CONFIG: string = "src/Config.luau"
local EXAMPLE: string = "tests/Fixtures/Config/Example.luau"

type Variant = { label: string, path: string, value: any }

-- The values every whole number from 1 refuses
local WRONG: { any } = { 0, 1.5, -2, "3", 0 / 0, math.huge }

local KEYS: { string } = { "perFrame.switches", "perFrame.draws", "perFrame.ragdolls", "perFrame.builds", "pool.spare" }

return function (): (boolean, string | nil)
	local Config = Environment.load(CONFIG)
	local Example = Environment.load(EXAMPLE)

	local taken: { Variant } = {
		{ label = "the example's caps and spare rigs", path = "perFrame.switches", value = 8 },
		{ label = "no caps", path = "perFrame", value = nil },
		{ label = "an empty perFrame", path = "perFrame", value = {} },
		{ label = "a cap of 1", path = "perFrame.draws", value = 1 },
		{ label = "no draws cap", path = "perFrame.draws", value = nil },
		{ label = "no spare rigs", path = "pool", value = nil },
	}

	for _, variant: Variant in taken do
		local client = Example.client()
		Example.set(client, variant.path, variant.value)

		local passed: boolean, failure: any = pcall(Config.client, Example.shared(), client)
		if not passed then
			return false, `Config.client refused {variant.label}: {failure}`
		end
	end

	local refusals: { Variant } = {
		{ label = "perFrame as a number", path = "perFrame", value = 4 },
		{ label = "an unknown cap", path = "perFrame.loads", value = 4 },
		{ label = "pool as a number", path = "pool", value = 40 },
		{ label = "a pool with no spare", path = "pool.spare", value = nil },
		{ label = "an unknown pool key", path = "pool.extra", value = 4 },
	}

	for _, key: string in KEYS do
		for _, value: any in WRONG do
			table.insert(refusals, { label = `{key} of {value}`, path = key, value = value })
		end
	end

	for _, refusal: Variant in refusals do
		local client = Example.client()
		Example.set(client, refusal.path, refusal.value)

		local problem: string? = Example.refusal(Config.client, `client.{refusal.path}`, Example.shared(), client)
		if problem then
			return false, `{refusal.label}: {problem}`
		end
	end

	return true, nil
end
