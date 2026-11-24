--[[
    A batch not back by the slice after its own has its visible and its
    hidden pair made due again there and sent to the other worker, with no
    fail-open, both tested again; its late result is dropped, its rays counted
--]]

--!strict
local Environment = require("../../Environment")
local StandIn = require("../../Fixtures/AntiEspWorkers/Pool")

local HARNESS: string = "tests/Fixtures/AntiEsp/Harness.luau"
local POOL: string = "ReplicatedStorage.Packages.Tread.Server.RelayWorkers.Pool"
local WORKERS: number = 2
local LOST: number = 1 -- The worker whose batch is held past the slice after its own
local OTHER: number = 2
local STEP: number = 1 / 64
local SEEN: vector = vector.create(20, 0, -30) -- Each ray to it ends at a positive x
local UNSEEN: vector = vector.create(-20, 0, -30) -- And to it at a negative x

return function (): (boolean, string | nil)
	-- Blocks the rays to the target at negative x, or once flipped the ones to the target at positive x
	local flipped: boolean = false
	local function wall(origin: vector, direction: vector): boolean
		local x: number = (origin + direction).x
		if flipped then
			return x > 0
		end

		return x < 0
	end

	local override: { [string]: any } = StandIn.override()
	local Harness: any = Environment.load(HARNESS, { [POOL] = override })
	local harness: any = Harness.new(function (_: any, server: any)
		server.antiEsp.workers = WORKERS
	end)

	local AntiEsp: any = Harness.AntiEsp
	local pool: any = override.made
	pool.wall = wall
	pool.readyCount = 1

	local own: number, viewer: any = harness:player("Viewer", vector.zero)
	local seen: number = harness:body("Player", SEEN)
	local unseen: number = harness:body("Player", UNSEEN)

	-- 1) Tested on the first worker: one shown, one hidden
	AntiEsp.isHidden(viewer, seen)
	AntiEsp.isHidden(viewer, unseen)
	harness:slice(0)
	harness:slice(STEP)

	if AntiEsp.isHidden(viewer, seen) or not AntiEsp.isHidden(viewer, unseen) then
		return false, "The first tests did not show the open pair and hide the walled one"
	end

	-- 2) Both due again at once and sent together to the first worker, which holds the batch
	pool.held[LOST] = true
	table.clear(pool.sends)
	table.clear(pool.rays)
	AntiEsp.moved(own)
	AntiEsp.isHidden(viewer, seen)
	AntiEsp.isHidden(viewer, unseen)

	local sentAt: number = 2 * STEP
	harness:slice(sentAt)

	if #pool.sends ~= 1 or pool.sends[1].worker ~= LOST or pool.sends[1].pairs ~= 2 then
		return false, "The two pairs due again were not sent together to the first worker"
	end

	local lostRays: number = #pool.rays
	local tests: number = AntiEsp.counts()
	AntiEsp.rays()

	-- 3) With no ask, so neither fails open, the next slice finds the batch not back and gives it up
	flipped = true
	pool.readyCount = WORKERS
	table.clear(pool.sends)
	table.clear(pool.rays)
	harness:slice(sentAt + STEP)

	local _, _, failOpens: number = AntiEsp.counts()

	if #pool.sends ~= 1 or pool.sends[1].worker ~= OTHER or pool.sends[1].pairs ~= 2 then
		return false, "The held batch's two pairs were not sent again to the other worker at the next slice"
	elseif failOpens ~= 0 or AntiEsp.counts() ~= tests then
		return false,
			`Before they were tested again {failOpens} pairs failed open and {AntiEsp.counts() - tests} settled`
	end

	-- 4) Both tested again at the slice after, under the flipped wall: the hidden one shown, the shown one held
	local freshRays: number = #pool.rays
	harness:slice(sentAt + 2 * STEP)

	if AntiEsp.counts() ~= tests + 2 then
		return false, `{AntiEsp.counts() - tests} tests settled from the batch sent again, not 2`
	elseif AntiEsp.isHidden(viewer, unseen) or AntiEsp.isHidden(viewer, seen) then
		return false, "The pairs tested again were not both shown under the flipped wall"
	elseif AntiEsp.rays() ~= freshRays then
		return false, `The batch sent again counted other rays than its {freshRays}`
	end

	-- 5) The held batch lands late and is dropped by its stamps, its rays still counted
	pool.held[LOST] = false
	harness:slice(sentAt + 3 * STEP)

	if AntiEsp.counts() ~= tests + 2 then
		return false, "The late batch settled a test"
	elseif AntiEsp.rays() ~= lostRays then
		return false, `The late batch counted other rays than the {lostRays} its worker cast`
	end

	return true, nil
end
