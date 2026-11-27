--[[
    The shared table's hash ignores its functions, each realm's own: other
    collision functions, rules and water, no water, no collision functions
    and a function under a key no value has, all hash alike
--]]

--!strict
local Environment = require("../../Environment")

local CONFIG: string = "src/Config.luau"
local EXAMPLE: string = "tests/Fixtures/Config/Example.luau"

type Variant = { label: string, path: string, value: any }

-- A function of another identity, to stand in for any of the shared table's own
local function other(): nil
	return nil
end

return function (): (boolean, string | nil)
	local Config = Environment.load(CONFIG)
	local Example = Environment.load(EXAMPLE)

	local base: number = Config.hash(Example.shared())

	local variants: { Variant } = {
		{ label = "another ray", path = "collision.ray", value = other },
		{ label = "another sweep", path = "collision.sweep", value = other },
		{ label = "another rest", path = "collision.rest", value = other },
		{ label = "another sphere", path = "collision.sphere", value = other },
		{ label = "other rules", path = "rules", value = other },
		{ label = "another water", path = "water", value = other },
		{ label = "no water", path = "water", value = nil },
		{ label = "no collision functions", path = "collision", value = {} },
		{ label = "a function where no value is", path = "step.extra", value = other },
	}

	for _, variant: Variant in variants do
		local shared = Example.shared()
		Example.set(shared, variant.path, variant.value)

		if Config.hash(shared) ~= base then
			return false, `The hash changed with {variant.label}`
		end
	end

	return true, nil
end
