--[[
    Each pair of keys whose second must stay above its first is refused
    with the two equal, or below where equal is allowed, naming the second
    key, and accepted just inside the edge
--]]

--!strict
local Environment = require("../../Environment")

local CONFIG: string = "src/Config.luau"
local EXAMPLE: string = "tests/Fixtures/Config/Example.luau"
local NUDGE: number = 0.01 -- How far past or short of the edge a value is moved
local TICK: number = 1 -- The same for a count of whole ticks

type Edge = {
	table: "shared" | "server" | "client",
	low: string,
	high: string,
	equal: boolean, -- Whether the second may equal the first
	step: number,
}

local EDGES: { Edge } = {
	{ table = "shared", low = "ticks.leadMin", high = "ticks.leadMax", equal = true, step = TICK },
	{ table = "shared", low = "step.standable", high = "step.walkable", equal = true, step = NUDGE },
	{ table = "shared", low = "step.crouched", high = "step.standing", equal = false, step = NUDGE },
	{ table = "shared", low = "step.clearance", high = "step.clearanceStart", equal = false, step = NUDGE },
	{ table = "shared", low = "step.swimLeave", high = "step.swimEnter", equal = false, step = NUDGE },
	{ table = "server", low = "relevancy.enter", high = "relevancy.leave", equal = false, step = NUDGE },
	{ table = "server", low = "tiers.nearEnter", high = "tiers.nearLeave", equal = false, step = NUDGE },
	{ table = "server", low = "tiers.nearFloor", high = "tiers.nearAim", equal = true, step = NUDGE },
	{ table = "server", low = "tiers.farFloor", high = "tiers.farAim", equal = true, step = NUDGE },
	{ table = "server", low = "budget.soft", high = "budget.hard", equal = true, step = NUDGE },
	{ table = "server", low = "antiEsp.lookAheadMin", high = "antiEsp.lookAheadMax", equal = true, step = NUDGE },
	{ table = "server", low = "npcs.near", high = "npcs.range", equal = true, step = NUDGE },
	{ table = "server", low = "rewind.delayMin", high = "rewind.delayMax", equal = true, step = NUDGE },
	{ table = "server", low = "rewind.band", high = "rewind.bandMax", equal = true, step = NUDGE },
	{ table = "client", low = "interpolation.delay", high = "interpolation.delayMax", equal = false, step = NUDGE },
	{ table = "client", low = "interpolation.scaleMin", high = "interpolation.scaleMax", equal = true, step = NUDGE },
	{ table = "client", low = "bodies.minSeconds", high = "bodies.maxSeconds", equal = false, step = NUDGE },
}

return function (): (boolean, string | nil)
	local Config = Environment.load(CONFIG)
	local Example = Environment.load(EXAMPLE)

	-- Fresh tables with an edge's second key set to its first's value plus the offset: that key's full path, the
	-- check its table goes through and the two tables the check takes
	local function build(edge: Edge, offset: number): (string, any, any, any)
		local tables: { [string]: any } =
			{ shared = Example.shared(), server = Example.server(), client = Example.client() }
		local root: any = tables[edge.table]
		Example.set(root, edge.high, Example.get(root, edge.low) + offset)

		if edge.table == "client" then
			return `client.{edge.high}`, Config.client, tables.shared, tables.client
		end

		return `{edge.table}.{edge.high}`, Config.server, tables.shared, tables.server
	end

	for _, edge: Edge in EDGES do
		-- At the edge: refused unless the pair lets the two be equal, and past it always refused
		local refusedOffsets: { number } = { -edge.step }
		local acceptedOffsets: { number } = { edge.step }

		if edge.equal then
			table.insert(acceptedOffsets, 0)
		else
			table.insert(refusedOffsets, 0)
		end

		for _, offset: number in refusedOffsets do
			local path: string, run: any, shared: any, settings: any = build(edge, offset)

			local problem: string? = Example.refusal(run, path, shared, settings)
			if problem then
				return false, `{edge.high} at {offset} from {edge.low}: {problem}`
			end
		end

		for _, offset: number in acceptedOffsets do
			local path: string, run: any, shared: any, settings: any = build(edge, offset)

			local passed: boolean, failure: any = pcall(run, shared, settings)
			if not passed then
				return false, `{path} at {offset} from {edge.low} was refused: {failure}`
			end
		end
	end

	return true, nil
end
