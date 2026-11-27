--[[
    The server's check and Config.bands, which the relay's dev seam runs, take
    up to 8 bands with one edge fewer, refuse every way out of that by its
    path, and accept each just inside its edge
--]]

--!strict
local Bands = require("../../Fixtures/Relay/Bands")
local Environment = require("../../Environment")

local CONFIG: string = "src/Config.luau"
local EXAMPLE: string = "tests/Fixtures/Config/Example.luau"
local PATH: string = "server.tiers"
local NUDGE: number = 0.01 -- How far past or short of an edge a value is moved
local MOST: number = 8 -- Constants.MAX_BANDS
local SPACING: number = 100 -- Studs between one edge of a long list and the next

-- Bands and edges, with the path the checks refuse them by, or none for a pair they accept
type Case = { path: string?, bands: { [any]: any }, edges: { [any]: any } }

-- count bands, each slower than the one before, with their edges
local function many(count: number): Case
	local case: Case = { path = nil, bands = {}, edges = {} }
	for index: number = 1, count do
		case.bands[index] = { aim = count - index + 1, floor = 1 }
		if index < count then
			case.edges[index] = { enter = index * SPACING, leave = index * SPACING + SPACING / 2 }
		end
	end

	return case
end

-- The three bands, with a band and an edge set where given, refused by path or, with none, accepted
local function three(path: string?, band: number | string | nil, bandValue: any, edge: number?, edgeValue: any): Case
	local case: Case = { path = path, bands = Bands.bands(), edges = Bands.edges() }
	if band ~= nil then
		case.bands[band] = bandValue
	end

	if edge ~= nil then
		case.edges[edge] = edgeValue
	end

	return case
end

-- The checks' answers on a case, nil when both answered it right
local function judge(Config: any, Example: any, case: Case): string?
	local server: any = Example.server()
	server.tiers.bands = case.bands
	server.tiers.edges = case.edges

	local path: string? = case.path
	if path then
		return Example.refusal(Config.server, path, Example.shared(), server)
			or Example.refusal(Config.bands, path, case.bands, case.edges)
	end

	local passed: boolean, failure: any = pcall(Config.server, Example.shared(), server)
	local seamPassed: boolean, seamFailure: any = pcall(Config.bands, case.bands, case.edges)
	if not passed or not seamPassed then
		return `Bands the checks should take were refused: {failure or seamFailure}`
	end

	return nil
end

return function (): (boolean, string | nil)
	local Config = Environment.load(CONFIG)
	local Example = Environment.load(EXAMPLE)

	local tooMany: Case = many(MOST + 1)
	tooMany.path = `{PATH}.bands[{MOST + 1}]`

	local fewer: Case = three(`{PATH}.edges[2]`, nil, nil, 2, nil)
	local more: Case = three(`{PATH}.edges[2]`, 3, nil, nil, nil)
	local edgeGap: Case = three(`{PATH}.edges[3]`, 4, { aim = 1, floor = 1 }, 2, nil)
	edgeGap.edges[3] = { enter = 1000, leave = 1100 }

	local cases: { Case } = {
		{ path = `{PATH}.bands[1]`, bands = {}, edges = {} },
		tooMany,
		three(`{PATH}.bands[3]`, 2, nil, nil, nil),
		edgeGap,
		fewer,
		more,
		three(`{PATH}.bands.x`, "x", { aim = 1, floor = 1 }, nil, nil),
		three(`{PATH}.bands[1].aim`, 1, { aim = 0, floor = 0 }, nil, nil),
		three(`{PATH}.edges[1]`, nil, nil, 1, 350),
		three(`{PATH}.bands[2].floor`, 2, { aim = 10, floor = 10 + NUDGE }, nil, nil),
		three(`{PATH}.edges[1].leave`, nil, nil, 1, { enter = 385, leave = 385 }),
		three(`{PATH}.edges[1].leave`, nil, nil, 1, { enter = 385 + NUDGE, leave = 385 }),
		three(`{PATH}.edges[2].enter`, nil, nil, 2, { enter = 385, leave = 660 }),
		three(`{PATH}.edges[2].enter`, nil, nil, 2, { enter = 385 - NUDGE, leave = 660 }),

		-- Just inside each edge: the three bands, the most, one with no edge, a floor at its aim, an enter just below
		-- its leave and one just above the leave before it
		three(nil, nil, nil, nil, nil),
		many(MOST),
		{ path = nil, bands = { { aim = 20, floor = 15 } }, edges = {} },
		three(nil, 1, { aim = 20, floor = 20 }, nil, nil),
		three(nil, nil, nil, 1, { enter = 385 - NUDGE, leave = 385 }),
		three(nil, nil, nil, 2, { enter = 385 + NUDGE, leave = 660 }),
	}

	for index: number, case: Case in cases do
		local problem: string? = judge(Config, Example, case)
		if problem then
			return false, `Case {index}: {problem}`
		end
	end

	return true, nil
end
