--[[
    Both entry points' checks refuse a ladder drop that is missing, no
    number, 0 or less, 90° or more, or not finite, naming
    shared.step.ladderDrop, and take one just inside either edge
--]]

--!strict
local Environment = require("../../Environment")

local CONFIG: string = "src/Config.luau"
local EXAMPLE: string = "tests/Fixtures/Config/Example.luau"
local PATH: string = "shared.step.ladderDrop"
local KEY: string = "step.ladderDrop"

-- Drops refused, each by what it gets wrong
local REFUSED: { [string]: any } = {
	["no number"] = "30",
	["level"] = 0,
	["a drop above level"] = -30,
	["straight down"] = 90,
	["past straight down"] = 120,
	["NaN"] = 0 / 0,
	["an infinity"] = math.huge,
}

local ACCEPTED: { number } = { 30, 0.01, 89.99 }

return function (): (boolean, string | nil)
	local Config = Environment.load(CONFIG)
	local Example = Environment.load(EXAMPLE)

	-- Why both checks did not refuse a drop naming its key, or nil when both did
	local function refusal(value: any): string?
		local shared = Example.shared()
		Example.set(shared, KEY, value)

		return Example.refusal(Config.server, PATH, shared, Example.server())
			or Example.refusal(Config.client, PATH, shared, Example.client())
	end

	local missing: string? = refusal(nil)
	if missing then
		return false, `A missing drop: {missing}`
	end

	for problem: string, value: any in REFUSED do
		local taken: string? = refusal(value)
		if taken then
			return false, `A drop of {problem}: {taken}`
		end
	end

	for _, degrees: number in ACCEPTED do
		local shared = Example.shared()
		Example.set(shared, KEY, degrees)

		local served: boolean, serverFailure: any = pcall(Config.server, shared, Example.server())
		local started: boolean, clientFailure: any = pcall(Config.client, shared, Example.client())
		if not served or not started then
			return false, `A drop of {degrees}° was refused: {serverFailure or clientFailure}`
		end
	end

	return true, nil
end
