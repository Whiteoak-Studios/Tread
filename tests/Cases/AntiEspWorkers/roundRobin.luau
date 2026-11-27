--[[
    Seven pairs due at once go round robin to 3 idle ready workers in the
    order their heap pops them, nearest first, so the first worker packs
    the first, fourth and seventh in that order, and each is sent one batch
--]]

--!strict
local Environment = require("../../Environment")
local StandIn = require("../../Fixtures/AntiEspWorkers/Pool")

local HARNESS: string = "tests/Fixtures/AntiEsp/Harness.luau"
local POOL: string = "ReplicatedStorage.Packages.Tread.Server.RelayWorkers.Pool"
local FOLDER: string = "TreadAntiEspWorkers"
local WORKERS: number = 3
local TARGETS: number = 7
local SPACING: number = 10 -- Studs between the targets along -Z, the nearest that far from the viewer
local CLOSE: number = 1e-6

return function (): (boolean, string | nil)
	local override: { [string]: any } = StandIn.override()
	local Harness: any = Environment.load(HARNESS, { [POOL] = override })
	local harness: any = Harness.new(function (_: any, server: any)
		server.antiEsp.workers = WORKERS
	end)

	local pool: any = override.made
	if pool.count ~= WORKERS or pool.name ~= FOLDER or pool.remote.Name ~= "Casts" then
		return false, `The pool was made as {pool.count} workers in {pool.name} loading {pool.remote}`
	end

	local _, viewer: any = harness:player("Viewer", vector.zero)

	-- The first standing point, the head's top, its side to the viewer's right, +X, as it looks along -Z
	local first: any = harness.server.antiEsp.aim.Stand[1]

	-- Asked farthest first, so the heap's order is the only one that puts them nearest first
	local heads: { vector } = {}
	for index: number = TARGETS, 1, -1 do
		local at: vector = vector.create(0, 0, -index * SPACING)
		Harness.AntiEsp.isHidden(viewer, harness:body("Player", at))
		heads[index] = vector.create(first.side, first.up, -index * SPACING)
	end

	harness:slice(0)

	if #pool.sends ~= WORKERS then
		return false, `{#pool.sends} batches were sent, not one to each of the {WORKERS} workers`
	end

	-- No walls, so each pair casts its head ray alone, in the order its worker packed it
	local order: { [number]: { number } } = {}
	for _, ray: any in pool.rays do
		local found: number? = nil
		for index: number, head: vector in heads do
			if vector.magnitude(ray.to - head) < CLOSE then
				found = index
			end
		end

		if found == nil then
			return false, `A ray ended at {ray.to}, no target's head`
		end

		order[ray.worker] = order[ray.worker] or {}
		table.insert(order[ray.worker], found)
	end

	for worker: number = 1, WORKERS do
		local packed: { number } = order[worker] or {}
		local expected: { number } = {}
		for index: number = worker, TARGETS, WORKERS do
			table.insert(expected, index)
		end

		if table.concat(packed, ",") ~= table.concat(expected, ",") then
			return false,
				`Worker {worker} packed the targets {table.concat(packed, ",")}, not {table.concat(expected, ",")}`
		end
	end

	for _, sent: any in pool.sends do
		if sent.pairs ~= #(order[sent.worker] or {}) then
			return false, `Worker {sent.worker}'s batch said {sent.pairs} pairs`
		end
	end

	return true, nil
end
