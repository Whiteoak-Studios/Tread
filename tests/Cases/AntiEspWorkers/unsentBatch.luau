--[[
    A slice that throws after packing tests and before sending them leaves
    those pairs to wait again at the next slice's collect, so a next slice
    with the switch off tests them in process instead of stranding them
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
local THROWN: string = "a target whose state throws on purpose"

-- A target's state whose posture, which only aiming its test reads, throws
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

return function (): (boolean, string | nil)
	local override: { [string]: any } = StandIn.override()
	local Harness: any = Environment.load(HARNESS, { [POOL] = override })
	local harness: any = Harness.new(function (_: any, server: any)
		server.antiEsp.workers = WORKERS
	end)

	local AntiEsp: any = Harness.AntiEsp
	local pool: any = override.made
	pool.wall = Harness.solid
	harness.wall = Harness.solid

	local own: number, viewer: any = harness:player("Viewer", vector.zero)
	local targets: { number } = {}
	for index: number = 1, TARGETS do
		table.insert(targets, harness:body("Player", vector.create(0, 0, -index * SPACING)))
	end

	local function ask()
		for _, target: number in targets do
			AntiEsp.isHidden(viewer, target)
		end
	end

	-- 1) Every pair tested hidden on the worker
	ask()
	harness:slice(0)
	harness:slice(STEP)

	-- 2) All due again, nearest first, and the farthest's aim throws once the others are packed
	local farthest: number = targets[TARGETS]
	local state: any = harness.states[farthest]
	harness.states[farthest] = throwing(state)
	ask()
	AntiEsp.moved(own)
	table.clear(pool.sends)

	local ran: boolean, failure: any = pcall(harness.slice, harness, 2 * STEP)
	harness.states[farthest] = state

	if ran or failure ~= THROWN then
		return false, `The slice whose aim threw ended as "{failure}"`
	elseif #pool.sends ~= 0 then
		return false, "The slice that threw sent its packed tests"
	end

	-- 3) The switch off: the next slice tests the two packed pairs in process
	AntiEsp.useWorkers(false)
	local tests: number = AntiEsp.counts()
	ask()
	harness:slice(3 * STEP)

	if AntiEsp.counts() ~= tests + TARGETS - 1 or #pool.sends ~= 0 then
		return false,
			`The next slice settled {AntiEsp.counts() - tests} tests, not the {TARGETS - 1} packed before the throw`
	end

	return true, nil
end
