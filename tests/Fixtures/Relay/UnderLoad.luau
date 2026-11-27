--[[
    The far rate under load's runs through the relay harness: one viewer with
    a target in each of two bands, and a script of relay runs over and under
    a budget, each target's records a run kept as a pattern
--]]

--!strict
local serde = require("@lune/serde")

local UnderLoad = {}

local BUDGET: number = 1 -- Stand-in seconds
local OVER: number = 2 -- Stand-in seconds a read moves on in a run over it, which measures one read's worth or more
local UNDER: number = 0 -- And in a run under it, which measures no time
local SETTLE: number = 3 -- Runs with no budget first, past both targets' reveals
local STRIDE: number = 0.1 -- Studs the targets move a run, back and forth, so each always has a change to send
local NEAR: vector = vector.create(0, 0, -100) -- Inside the example's first edge
local FAR: vector = vector.create(0, 0, -400) -- Past it, in the farthest band
local LOWERED_RUN: number = 5 -- A run after which the script holds the farthest band lowered

-- The runs after the settle, O over the budget and U under it: three over lower the farthest band from the fourth, an
-- over among the unders holds it, and three under in a row put it back from the tenth
UnderLoad.SCRIPT = "OOOUUOUUUOOU"
UnderLoad.SETTINGS = { runs = 3, scale = 0.5 }

-- What a drive's runs gave: each target's records a run, every block's digest, the caps' totals, and the bands
-- Relay.bands gave while the farthest was lowered
export type Ran = {
	near: string,
	far: string,
	digest: string,
	left: number,
	over: number,
	halved: number,
	bands: string,
}

-- Gives a server table two bands with the farther at the relay's rate, so each of its records shows a halving
function UnderLoad.two(_: any, server: any)
	server.tiers.bands = { { aim = 20, floor = 15 }, { aim = 20, floor = 20 } }
end

-- Gives a server table one band at the relay's rate, and no edge
function UnderLoad.one(_: any, server: any)
	server.tiers.bands = { { aim = 20, floor = 15 } }
	server.tiers.edges = {}
end

--[[
    Runs the script on a harness of the module given, in process or on
    that many workers, its tables changed by tweak
--]]

function UnderLoad.drive(Harness: any, workers: number?, tweak: (shared: any, server: any) -> ()): Ran
	local harness: any = Harness.new(nil, tweak, workers)
	local Relay: any = Harness.Relay
	local parts: { string } = {}

	harness._deliver = function (self: any, keys: { any }, data: buffer)
		table.insert(parts, buffer.tostring(data))
		Harness._deliver(self, keys, data)
	end

	local client: any = harness:viewer("Viewer")
	local near: number = harness:spawn("Player", NEAR)
	local far: number = harness:spawn("Player", FAR)
	local nears: { string } = {}
	local fars: { string } = {}
	local bands: string = ""

	for run: number = 1, SETTLE + #UnderLoad.SCRIPT do
		if run == SETTLE + 1 then
			Relay.setBudget(BUDGET)
			Relay.setUnderLoad(UnderLoad.SETTINGS)
		end

		local step: number = run % 2 == 0 and -STRIDE or STRIDE
		harness.states[near].position += vector.create(step, 0, 0)
		harness.states[far].position += vector.create(step, 0, 0)

		local scripted: number = run - SETTLE
		harness.step = UNDER
		if scripted >= 1 and string.sub(UnderLoad.SCRIPT, scripted, scripted) == "O" then
			harness.step = OVER
		end

		table.insert(parts, `run {run}`)
		harness:run()

		if scripted >= 1 then
			table.insert(nears, `{Harness.count(client.seen.records, near)}`)
			table.insert(fars, `{Harness.count(client.seen.records, far)}`)
		end

		if scripted == LOWERED_RUN then
			local given: { { aim: number, floor: number } } = Relay.bands()
			local listed: { string } = {}
			for index: number, band: { aim: number, floor: number } in given do
				listed[index] = `{band.aim}/{band.floor}`
			end

			bands = table.concat(listed, ",")
		end
	end

	local left: number, over: number, halved: number = Relay.caps()

	return {
		near = table.concat(nears),
		far = table.concat(fars),
		digest = serde.hash("sha256", table.concat(parts, "\n")),
		left = left,
		over = over,
		halved = halved,
		bands = bands,
	}
end

return UnderLoad
