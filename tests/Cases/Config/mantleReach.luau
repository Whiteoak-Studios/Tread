--[[
    Both entry points' checks refuse a mantle reach that is missing, not a
    number, 0 or less, not finite, or so long its move to the face in one
    tick passes OwnerState's speed, naming shared.step.mantleReach
--]]

--!strict
local Environment = require("../../Environment")

local CONFIG: string = "src/Config.luau"
local EXAMPLE: string = "tests/Fixtures/Config/Example.luau"
local PATH: string = "shared.step.mantleReach"

-- A value for the key, nil to leave it out, and whether it is refused
type Edge = { label: string, value: any, refused: boolean }

-- At the example's 20 Hz, a move of 25.6 studs in a tick is 512 studs/s, which OwnerState's i16 velocity can't hold
local EDGES: { Edge } = {
	{ label = "missing", value = nil, refused = true },
	{ label = "a string", value = "1.39", refused = true },
	{ label = "0", value = 0, refused = true },
	{ label = "negative", value = -1, refused = true },
	{ label = "NaN", value = 0 / 0, refused = true },
	{ label = "infinite", value = math.huge, refused = true },
	{ label = "a tick's move at 512 studs/s", value = 25.6, refused = true },
	{ label = "past a tick's bound", value = 26, refused = true },
	{ label = "just under a tick's bound", value = 25.59, refused = false },
	{ label = "the hull's radius", value = 1.39, refused = false },
	{ label = "a quantum", value = 1 / 512, refused = false },
}

return function (): (boolean, string | nil)
	local Config = Environment.load(CONFIG)
	local Example = Environment.load(EXAMPLE)

	for _, edge: Edge in EDGES do
		local shared = Example.shared()
		shared.step.mantleReach = edge.value

		if edge.refused then
			local problem: string? = Example.refusal(Config.server, PATH, shared, Example.server())
				or Example.refusal(Config.client, PATH, shared, Example.client())
			if problem then
				return false, `A mantle reach {edge.label}: {problem}`
			end
		else
			local served: boolean, serverFailure: any = pcall(Config.server, shared, Example.server())
			local started: boolean, clientFailure: any = pcall(Config.client, shared, Example.client())
			if not served or not started then
				return false, `A mantle reach {edge.label} was refused: {serverFailure or clientFailure}`
			end
		end
	end

	local before = Example.shared()
	local after = Example.shared()
	after.step.mantleReach += 1 / 512
	if Config.hash(before) == Config.hash(after) then
		return false, "The shared table hashed alike with two mantle reaches"
	end

	return true, nil
end
