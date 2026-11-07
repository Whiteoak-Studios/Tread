--[[
    Both entry points' checks refuse a mantle arc that is missing, not a
    number, negative or not finite, naming shared.step.mantleArc, and take
    0 or more, and the shared table's hash changes with it
--]]

--!strict
local Environment = require("../../Environment")

local CONFIG: string = "src/Config.luau"
local EXAMPLE: string = "tests/Fixtures/Config/Example.luau"
local PATH: string = "shared.step.mantleArc"

-- A value for the key, nil to leave it out, and whether it is refused
type Edge = { label: string, value: any, refused: boolean }

local EDGES: { Edge } = {
	{ label = "missing", value = nil, refused = true },
	{ label = "a string", value = "0.5", refused = true },
	{ label = "a table", value = {}, refused = true },
	{ label = "negative", value = -1 / 512, refused = true },
	{ label = "NaN", value = 0 / 0, refused = true },
	{ label = "infinite", value = math.huge, refused = true },
	{ label = "negatively infinite", value = -math.huge, refused = true },
	{ label = "0", value = 0, refused = false },
	{ label = "Frontier Zero's 0.5", value = 0.5, refused = false },
	{ label = "past a hull's height", value = 7, refused = false },
}

return function (): (boolean, string | nil)
	local Config = Environment.load(CONFIG)
	local Example = Environment.load(EXAMPLE)

	for _, edge: Edge in EDGES do
		local shared = Example.shared()
		shared.step.mantleArc = edge.value

		if edge.refused then
			local problem: string? = Example.refusal(Config.server, PATH, shared, Example.server())
				or Example.refusal(Config.client, PATH, shared, Example.client())
			if problem then
				return false, `A mantle arc {edge.label}: {problem}`
			end
		else
			local served: boolean, serverFailure: any = pcall(Config.server, shared, Example.server())
			local started: boolean, clientFailure: any = pcall(Config.client, shared, Example.client())
			if not served or not started then
				return false, `A mantle arc {edge.label} was refused: {serverFailure or clientFailure}`
			end
		end
	end

	local before = Example.shared()
	local after = Example.shared()
	after.step.mantleArc += 1 / 512
	if Config.hash(before) == Config.hash(after) then
		return false, "The shared table hashed alike with two mantle arcs"
	end

	return true, nil
end
