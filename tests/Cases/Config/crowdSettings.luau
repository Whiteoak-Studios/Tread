--[[
    The server's check and Config.crowd, which the relay's dev seam runs, take
    tiers.crowd left out or whole, refuse every way out of it by its path, and
    accept each value just inside its edge
--]]

--!strict
local Environment = require("../../Environment")

local CONFIG: string = "src/Config.luau"
local CONSTANTS: string = "src/Constants.luau"
local EXAMPLE: string = "tests/Fixtures/Config/Example.luau"
local PATH: string = "server.tiers.crowd"
local NUDGE: number = 0.01 -- How far past or short of an edge a value is moved

-- A crowd cap, with the path the checks refuse it by, or none for one they accept
type Case = { path: string?, crowd: any }

-- The dev place's cap with one key set, nil to remove it
local function cap(path: string?, key: string?, value: any): Case
	local crowd: { [string]: any } = { size = 32, rate = 20, floor = 5 }
	if key ~= nil then
		crowd[key] = value
	end

	return { path = path, crowd = crowd }
end

-- The checks' answers on a case, nil when both answered it right
local function judge(Config: any, Example: any, case: Case): string?
	local server: any = Example.server()
	server.tiers.crowd = case.crowd

	local path: string? = case.path
	if path then
		return Example.refusal(Config.server, path, Example.shared(), server)
			or Example.refusal(Config.crowd, path, case.crowd)
	end

	local passed: boolean, failure: any = pcall(Config.server, Example.shared(), server)
	local seamPassed: boolean, seamFailure: any = pcall(Config.crowd, case.crowd)
	if not passed or not seamPassed then
		return `A cap the checks should take was refused: {failure or seamFailure}`
	end

	return nil
end

return function (): (boolean, string | nil)
	local Config = Environment.load(CONFIG)
	local Example = Environment.load(EXAMPLE)
	local most: number = Environment.load(CONSTANTS).MAX_CROWD -- The largest size the relay takes

	-- Left out, the server's check takes the tables as the example gives them
	local plain: boolean, failure: any = pcall(Config.server, Example.shared(), Example.server())
	if not plain then
		return false, `The example's tables with no crowd cap were refused: {failure}`
	end

	local cases: { Case } = {
		{ path = PATH, crowd = 32 },
		cap(`{PATH}.size`, "size", nil),
		cap(`{PATH}.size`, "size", 0),
		cap(`{PATH}.size`, "size", 1.5),
		cap(`{PATH}.size`, "size", most + 1),
		cap(`{PATH}.size`, "size", "32"),
		cap(`{PATH}.rate`, "rate", 0),
		cap(`{PATH}.rate`, "rate", -1),
		cap(`{PATH}.rate`, "rate", math.huge),
		cap(`{PATH}.rate`, "rate", 0 / 0),
		cap(`{PATH}.floor`, "floor", 0),
		cap(`{PATH}.floor`, "floor", nil),
		cap(`{PATH}.floor`, "floor", 20 + NUDGE),
		cap(`{PATH}.extra`, "extra", 1),

		-- Just inside each edge: the dev place's cap, the smallest and the largest size, a floor at its rate and a
		-- floor and rate just above 0
		cap(nil, nil, nil),
		cap(nil, "size", 1),
		cap(nil, "size", most),
		cap(nil, "floor", 20),
		{ path = nil, crowd = { size = 1, rate = NUDGE, floor = NUDGE } },
	}

	for index: number, case: Case in cases do
		local problem: string? = judge(Config, Example, case)
		if problem then
			return false, `Case {index}: {problem}`
		end
	end

	return true, nil
end
