--[[
    With relay.clocks on, the four seeded layouts give their pinned digests
    in process and on 2 stand-in workers, every section reads 0 or more, and
    each run's parts fit inside the work around them, on each worker too
--]]

--!strict
local Environment = require("../../Environment")
local Layouts = require("../../Fixtures/Relay/Layouts")

local HARNESS: string = "tests/Fixtures/Relay/Harness.luau"
local WIRE: string = "src/Server/Relay/Wire.luau"
local WORKERS: number = 2
local ROUNDING: number = 1e-9 -- Seconds a sum of laps in f64 may pass the whole they telescope to

-- A turn's parts, and a worker run's own around them
local TURN_PARTS: { string } = { "head", "gather", "measure", "settle", "schedule", "place", "send" }
local RUN_PARTS: { string } = { "unpack", "bodies", "grid", "ready", "turns", "views", "pack" }

-- The sections a layout on the workers reaches in some run. A stand-in fires nothing and lands a round as it
-- finishes, so fire and back read 0, the flushes are the server handle's, and the deferred calls may take no tick
local ON_WORKERS: { string } = {
	"run",
	"walk",
	"file",
	"inProcess",
	"answers",
	"shared",
	"own",
	"handIn",
	"open",
	"land",
	"asks",
	"sends",
	"round",
	"waitBeat",
	"delivery",
}

-- The sections only a round on the workers reaches, which read 0 in every run in process
local WORKERS_ONLY: { string } = {
	"run",
	"fire",
	"answers",
	"shared",
	"own",
	"handIn",
	"open",
	"land",
	"asks",
	"sends",
	"deferred",
	"round",
	"waitBeat",
	"delivery",
	"back",
}

local IN_PROCESS: { string } = { "walk", "file", "inProcess" } -- And beside the turn's parts, those it reaches there

type Result = Layouts.Result

-- What a layout's harness gave the case: its relay, and the first rule a worker's round broke
type Seen = {
	Relay: any,
	problem: string?,
}

--[[
    Why a worker's last round broke a rule of its clocks, or nil: none
    given, a part below 0, its turns' parts past its turns, or its run's
    parts past its whole run
--]]

local function workerWrong(pool: any, workers: number, Wire: any): string?
	for worker: number = 1, workers do
		local start: number, finish: number, clocks: buffer? = pool:times(worker)
		if clocks == nil or buffer.len(clocks) ~= Wire.CLOCK_BYTES then
			return `Worker {worker}'s round came in without its {Wire.CLOCK_BYTES} B of clocks`
		end

		local sums: { number } = { 0, 0 }
		for at: number, parts: { string } in { TURN_PARTS, RUN_PARTS } do
			for _, name: string in parts do
				local seconds: number = buffer.readf64(clocks, Wire.CLOCK_AT[name])
				if not (seconds >= 0) then
					return `Worker {worker}'s {name} read {seconds} s`
				end

				sums[at] += seconds
			end
		end

		local turns: number = buffer.readf64(clocks, Wire.CLOCK_AT.turns)
		if sums[1] > turns + ROUNDING then
			return `Worker {worker}'s turns' parts took {sums[1]} s, past its turns' {turns} s`
		elseif sums[2] > finish - start + ROUNDING then
			return `Worker {worker}'s run's parts took {sums[2]} s, past its whole run's {finish - start} s`
		end
	end

	return nil
end

--[[
    Runs a layout with the relay's clocks on: each harness it makes gets
    relay.clocks through its tweak, and each of its runs has the workers'
    clocks checked once the round is in
--]]

local function clocked(layout: (workers: number?) -> Result, workers: number?, Wire: any): (Result, Seen)
	local seen: Seen = { Relay = nil, problem = nil }
	local load: any = Environment.load

	Environment.load = function (path: string, overrides: { [string]: any }?): any
		local loaded: any = load(path, overrides)
		if path ~= HARNESS then
			return loaded
		end

		local new: any = loaded.new
		loaded.new = function (network: boolean?, tweak: any, count: number?): any
			local harness: any = new(network, function (shared: any, server: any)
				if tweak then
					tweak(shared, server)
				end

				server.relay = table.clone(server.relay or {})
				server.relay.clocks = true
			end, count)

			harness.run = function (self: any)
				loaded.run(self)
				if count and seen.problem == nil then
					seen.problem = workerWrong(self.pool, count, Wire)
				end
			end

			seen.Relay = loaded.Relay

			return harness
		end

		return loaded
	end

	local ran: boolean, result: any = pcall(layout, workers)
	Environment.load = load

	if not ran then
		error(result, 0)
	end

	return result, seen
end

-- A section's seconds summed over the runs its ring holds
local function total(ring: any): number
	local sum: number = 0
	for index: number = 1, ring.held do
		sum += ring.times[index]
	end

	return sum
end

--[[
    Why a layout's rings broke a rule of the relay's clocks, or nil: a
    section with no ring or another count of runs, one below 0, a run's
    turns' parts past its turns and in-process work, a section that layout
    reaches read 0 over every run, or one only workers reach read above 0
    in process
--]]

local function ringsWrong(Relay: any, workers: boolean): string?
	local rings: { [string]: any } = Relay.clocks()
	local held: number = rings.head and rings.head.held or 0
	if held == 0 then
		return "The rings kept no run"
	end

	for _, name: string in Relay.CLOCKS do
		local ring: any = rings[name]
		if ring == nil or ring.held ~= held then
			return `The {name} section kept no ring of the {held} runs the others did`
		end

		for index: number = 1, held do
			if not (ring.times[index] >= 0) then
				return `Run {index}'s {name} read {ring.times[index]} s`
			end
		end
	end

	for index: number = 1, held do
		local sum: number = 0
		for _, name: string in TURN_PARTS do
			sum += rings[name].times[index]
		end

		local around: number = rings.turns.times[index] + rings.inProcess.times[index]
		if sum > around + ROUNDING then
			return `Run {index}'s turns' parts took {sum} s, past its turns' and in-process work's {around} s`
		end
	end

	local reached: { string } = table.clone(TURN_PARTS)
	for _, list: { string } in workers and { RUN_PARTS, ON_WORKERS } or { IN_PROCESS } do
		table.move(list, 1, #list, #reached + 1, reached)
	end

	for _, name: string in reached do
		if not (total(rings[name]) > 0) then
			return `The {name} section read 0 over every run`
		end
	end

	if not workers then
		for _, name: string in WORKERS_ONLY do
			if total(rings[name]) ~= 0 then
				return `The {name} section read {total(rings[name])} s in process, where no round goes out`
			end
		end
	end

	return nil
end

return function (): (boolean, string | nil)
	local Wire: any = Environment.load(WIRE)
	local layouts: { [string]: (workers: number?) -> Result } = {
		idle = Layouts.idle,
		fight = Layouts.fight,
		field = Layouts.field,
		taps = Layouts.taps,
	}

	for name: string, layout: (workers: number?) -> Result in layouts do
		for _, count: number in { 0, WORKERS } do
			local workers: number? = count > 0 and count or nil
			local where: string = workers and `on {workers} workers` or "in process"
			local result: Result, seen: Seen = clocked(layout, workers, Wire)

			if result.digest ~= Layouts.EXPECTED[name] then
				return false, `With clocks on {where}, the {name} layout digests to {result.digest}`
			elseif workers and result.worked ~= workers then
				return false, `With clocks on, the {name} layout had {result.worked} of its {workers} workers run`
			elseif seen.problem then
				return false, `With clocks on, the {name} layout {where}: {seen.problem}`
			end

			local why: string? = ringsWrong(seen.Relay, workers ~= nil)
			if why then
				return false, `With clocks on, the {name} layout {where}: {why}`
			end
		end
	end

	return true, nil
end
