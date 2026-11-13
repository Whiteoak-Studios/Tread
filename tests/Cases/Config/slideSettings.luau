--[[
    The crouch slide's table is optional, and given, both entry points'
    checks refuse each bad key naming it: a stop not below the start, a top
    speed below it, a cooldown past 255 ticks, and the kinds each key takes
--]]

--!strict
local Environment = require("../../Environment")

local CONFIG: string = "src/Config.luau"
local EXAMPLE: string = "tests/Fixtures/Config/Example.luau"
local PATH: string = "shared.step.slide"

-- The dev place's slide, a fresh table each call
local function slide(): { [string]: any }
	return { start = 15, boost = 0, friction = 6, slope = 0.5, max = 27, stop = 6, steer = 60, cooldown = 2 }
end

-- A key set to a value, nil to leave it out, and whether the checks refuse it
type Edge = { key: string, value: any, refused: boolean }

local EDGES: { Edge } = {
	{ key = "start", value = nil, refused = true },
	{ key = "start", value = "15", refused = true },
	{ key = "start", value = 0, refused = true },
	{ key = "start", value = 0 / 0, refused = true },
	{ key = "boost", value = -1, refused = true },
	{ key = "boost", value = math.huge, refused = true },
	{ key = "boost", value = 3, refused = false },
	{ key = "friction", value = -1, refused = true },
	{ key = "friction", value = 0, refused = false },
	{ key = "slope", value = -0.1, refused = true },
	{ key = "slope", value = 1.1, refused = true },
	{ key = "slope", value = 1, refused = false },
	{ key = "max", value = 512, refused = true }, -- Its quantized value reaches 512 studs/s, as any speed's may not
	{ key = "max", value = 14, refused = true }, -- Below the start
	{ key = "max", value = 15, refused = false }, -- At the start
	{ key = "stop", value = 15, refused = true }, -- Not below the start
	{ key = "stop", value = 0, refused = true },
	{ key = "stop", value = 14.9, refused = false },
	{ key = "steer", value = -1, refused = true },
	{ key = "steer", value = 0, refused = false },
	{ key = "cooldown", value = -1, refused = true },
	{ key = "cooldown", value = 12.8, refused = true }, -- 256 ticks at 20 Hz, past its u8
	{ key = "cooldown", value = 12.75, refused = false }, -- 255
	{ key = "cooldown", value = 0, refused = false },
	{ key = "spin", value = 1, refused = true }, -- A key Tread reads none of
}

return function (): (boolean, string | nil)
	local Config = Environment.load(CONFIG)
	local Example = Environment.load(EXAMPLE)

	-- Absent, which the example is, and present with the dev place's values, both pass
	local plain = Example.shared()
	if plain.step.slide ~= nil then
		return false, "The approved example gives a slide, so it is no longer Frontier Zero's"
	end

	local given = Example.shared()
	given.step.slide = slide()
	local client = Example.client()
	client.animations.slide = client.animations.crouchWalk
	local served: boolean, serverFailure: any = pcall(Config.server, given, Example.server())
	local started: boolean, clientFailure: any = pcall(Config.client, given, client)
	if not served or not started then
		return false, `The dev place's slide was refused: {serverFailure or clientFailure}`
	end

	for _, edge: Edge in EDGES do
		local shared = Example.shared()
		local values: { [string]: any } = slide()
		values[edge.key] = edge.value
		shared.step.slide = values

		local path: string = `{PATH}.{edge.key}`
		local label: string = `A slide's {edge.key} of {edge.value}`
		local withSlide = Example.client()
		withSlide.animations.slide = withSlide.animations.crouchWalk

		if edge.refused then
			local problem: string? = Example.refusal(Config.server, path, shared, Example.server())
				or Example.refusal(Config.client, path, shared, withSlide)
			if problem then
				return false, `{label}: {problem}`
			end
		else
			local ok: boolean, failure: any = pcall(Config.server, shared, Example.server())
			local okClient: boolean, clientProblem: any = pcall(Config.client, shared, withSlide)
			if not ok or not okClient then
				return false, `{label} was refused: {failure or clientProblem}`
			end
		end
	end

	-- A slide value joins the hash, and so does the slide's being given at all
	local changed = Example.shared()
	changed.step.slide = slide()
	changed.step.slide.friction += 1 / 512
	if Config.hash(given) == Config.hash(changed) then
		return false, "The shared table hashed alike with two slide frictions"
	elseif Config.hash(given) == Config.hash(plain) then
		return false, "The shared table hashed alike with a slide and without one"
	end

	return true, nil
end
