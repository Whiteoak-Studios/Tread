--[[
    A packing slice's kept answers, held to land beside its batches, are
    given up as the batches are, after a throw before the send or past the
    fail-open time, counted as no kept test, and tested again, every count
    as without memory
--]]

--!strict
local Environment = require("../../Environment")
local StandIn = require("../../Fixtures/AntiEspWorkers/Pool")

local HARNESS: string = "tests/Fixtures/AntiEsp/Harness.luau"
local POOL: string = "ReplicatedStorage.Packages.Tread.Server.RelayWorkers.Pool"
local WORKERS: number = 1
local TARGETS: number = 3
local SPACING: number = 10 -- Studs between the targets along -Z, so the farthest, which throws, is aimed last
local STEP: number = 1 / 64
local LATE: number = 0.2 -- Seconds to a slice past the example's 0.15 s fail-open time
local SLICE: number = 60 -- Seconds a slice may take, so neither rig's tests run out on a loaded machine
local THROWN: string = "a target whose state throws on purpose"
local ON: boolean = true -- Verdict memory's switch
local OFF: boolean = false
local IN_PROCESS: boolean = false -- The workers' switch off, so a slice casts in the server's own script

-- A target's state whose posture, which a test reads before anything else of it, throws
local function throwing(state: any): any
	return setmetatable({}, {
		__index = function (_: any, field: string): any
			if field == "posture" then
				error(THROWN, 0)
			end

			return state[field]
		end,
	})
end

-- A harness on one worker that blocks every ray, memory set, with a viewer and its targets along -Z
local function scene(remember: boolean): (any, any, number, { number })
	local override: { [string]: any } = StandIn.override()
	local Harness: any = Environment.load(HARNESS, { [POOL] = override })
	local harness: any = Harness.new(function (_: any, server: any)
		server.antiEsp.workers = WORKERS
	end)

	Harness.AntiEsp.useMemory(remember)
	override.made.wall = Harness.solid
	harness.wall = Harness.solid

	local own: number, viewer: any = harness:player("Viewer", vector.zero)
	local targets: { number } = {}
	for index: number = 1, TARGETS do
		table.insert(targets, harness:body("Player", vector.create(0, 0, -index * SPACING)))
	end

	return harness, viewer, own, targets
end

local function ask(harness: any, viewer: any, targets: { number })
	for _, target: number in targets do
		harness.AntiEsp.isHidden(viewer, target)
	end
end

return function (): (boolean, string | nil)
	-- 1) Tested hidden on the worker, then all due again, the nearer two kept and held, and the farthest throws
	local harness: any, viewer: any, own: number, targets: { number } = scene(ON)
	local AntiEsp: any = harness.AntiEsp
	ask(harness, viewer, targets)
	harness:slice(0, SLICE)
	harness:slice(STEP, SLICE)

	local farthest: number = targets[TARGETS]
	local state: any = harness.states[farthest]
	harness.states[farthest] = throwing(state)
	ask(harness, viewer, targets)
	AntiEsp.moved(own)
	harness:remembered()

	-- The nearer two are held, and none of theirs is applied in a slice that threw before its send
	local ran: boolean, failure: any = pcall(harness.slice, harness, 2 * STEP, SLICE)
	harness.states[farthest] = state
	local held: number = harness:remembered()

	if ran or failure ~= THROWN then
		return false, `The slice whose aim threw ended as "{failure}"`
	elseif held ~= 0 then
		return false, `The slice that threw counted {held} kept tests, though it applied none of the answers it held`
	end

	-- The next slice gives up the two held, tests them again in process with the switch off and counts those it applies
	AntiEsp.useWorkers(IN_PROCESS)
	local tests: number = AntiEsp.counts()
	ask(harness, viewer, targets)
	harness:slice(3 * STEP, SLICE)
	local again: number = harness:remembered()

	if AntiEsp.counts() ~= tests + TARGETS - 1 or again ~= TARGETS - 1 then
		return false, `After the throw the next slice settled {AntiEsp.counts() - tests} tests and kept {again} answers`
	end

	-- 2) A slice past the fail-open time gives up the last slice's held answers as it gives up its batches
	local plain: any, plainViewer: any, _, plainTargets: { number } = scene(OFF)
	local remembering: any, keptViewer: any, _, keptTargets: { number } = scene(ON)
	local times: { number } = { 0, STEP, 2 * STEP, 0.5, 0.5 + LATE, 0.5 + LATE + STEP, 1 }
	local kept: number = 0

	for index: number, now: number in times do
		ask(plain, plainViewer, plainTargets)
		ask(remembering, keptViewer, keptTargets)
		plain:slice(now, SLICE)
		remembering:slice(now, SLICE)
		kept += remembering:remembered()

		local plainTests: number, hidden: number, failOpens: number = plain.AntiEsp.counts()
		local keptTests: number, keptHidden: number, keptFailOpens: number = remembering.AntiEsp.counts()
		if plainTests ~= keptTests or hidden ~= keptHidden or failOpens ~= keptFailOpens then
			local counts: string =
				`{keptTests}, {keptHidden} and {keptFailOpens} against {plainTests}, {hidden} and {failOpens}`
			return false, `After slice {index} at {now} s, memory's counts were {counts}`
		end

		for _, target: number in plainTargets do
			if plain.AntiEsp.reason(plainViewer.key, target) ~= remembering.AntiEsp.reason(keptViewer.key, target) then
				return false, `After slice {index} at {now} s, slot {target}'s reason differed with memory`
			end
		end
	end

	if kept == 0 then
		return false, "No slice of the late run kept an answer"
	end

	return true, nil
end
