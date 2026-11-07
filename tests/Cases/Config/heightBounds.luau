--[[
    Every eye height and the mantle's reach are refused past the 7.96875
    studs OwnerState's u8 holds at 1/32 stud, and at the halfway value that
    rounds up past it, and accepted at that height and just below the edge
--]]

--!strict
local Environment = require("../../Environment")

local CONFIG: string = "src/Config.luau"
local CONSTANTS: string = "src/Constants.luau"
local EXAMPLE: string = "tests/Fixtures/Config/Example.luau"
local U8_LEVELS: number = 2 ^ 8 - 1 -- The highest a u8 holds

local HEIGHTS: { string } = { "eyeStanding", "eyeCrouched", "eyeDowned", "mantleHeight" }

return function (): (boolean, string | nil)
	local Config = Environment.load(CONFIG)
	local Constants = Environment.load(CONSTANTS)
	local Example = Environment.load(EXAMPLE)

	local quantum: number = Constants.EYE_QUANTUM
	local limit: number = U8_LEVELS * quantum

	-- One step past the limit, the halfway value that rounds up to it, and no height at all
	local refused: { number } = { limit + quantum, limit + quantum / 2, 0, -quantum }

	-- The limit itself, a value that rounds down to it, and the lowest step
	local accepted: { number } = { limit, limit + quantum / 4, quantum }

	for _, name: string in HEIGHTS do
		local path: string = `shared.step.{name}`

		for _, height: number in refused do
			local shared = Example.shared()
			shared.step[name] = height

			local problem: string? = Example.refusal(Config.server, path, shared, Example.server())
			if problem then
				return false, `At {height}: {problem}`
			end
		end

		for _, height: number in accepted do
			local shared = Example.shared()
			shared.step[name] = height

			local passed: boolean, failure: any = pcall(Config.server, shared, Example.server())
			if not passed then
				return false, `{path} at {height}, which OwnerState holds, was refused: {failure}`
			end
		end
	end

	return true, nil
end
