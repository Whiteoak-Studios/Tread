--[[
    Every speed the step moves a body at is refused at 512 studs/s and at
    the last value that rounds up to it, since OwnerState's i16 can't hold
    either, and accepted at the highest value it holds
--]]

--!strict
local Environment = require("../../Environment")

local CONFIG: string = "src/Config.luau"
local CONSTANTS: string = "src/Constants.luau"
local EXAMPLE: string = "tests/Fixtures/Config/Example.luau"

local SPEEDS: { string } = {
	"walk",
	"sprint",
	"crouch",
	"swim",
	"swimSprint",
	"ladder",
	"ladderSprint",
	"jump",
	"terminal",
	"ladderJump",
}

return function (): (boolean, string | nil)
	local Config = Environment.load(CONFIG)
	local Constants = Environment.load(CONSTANTS)
	local Example = Environment.load(EXAMPLE)

	local limit: number = Constants.VELOCITY_LIMIT
	local quantum: number = Constants.VELOCITY_QUANTUM

	-- The limit, the halfway value that rounds up to it, and no speed at all
	local refused: { number } = { limit, limit - quantum / 2, 0, -quantum }

	-- The highest speed the i16 holds, and the slowest
	local accepted: { number } = { limit - quantum, quantum }

	for _, name: string in SPEEDS do
		local path: string = `shared.step.{name}`

		for _, speed: number in refused do
			local shared = Example.shared()
			shared.step[name] = speed

			local problem: string? = Example.refusal(Config.server, path, shared, Example.server())
			if problem then
				return false, `At {speed}: {problem}`
			end
		end

		for _, speed: number in accepted do
			local shared = Example.shared()
			shared.step[name] = speed

			local passed: boolean, failure: any = pcall(Config.server, shared, Example.server())
			if not passed then
				return false, `{path} at {speed}, which OwnerState holds, was refused: {failure}`
			end
		end
	end

	return true, nil
end
