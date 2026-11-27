--[[
    A slice that packs for a worker, with sleepers waiting and more player
    pairs due than it has time for, packs sleepers first, none its mean says
    would end past the lying share, then gives the rest to player pairs
--]]

--!strict
local Environment = require("../../Environment")
local StandIn = require("../../Fixtures/AntiEspWorkers/Pool")

local HARNESS: string = "tests/Fixtures/AntiEsp/Harness.luau"
local POOL: string = "ReplicatedStorage.Packages.Tread.Server.RelayWorkers.Pool"
local WORKERS: number = 1
local SPIN: number = 0.002 -- Seconds of os.clock each slowed target's aim takes
local SHARE: number = 2.5 * SPIN -- The lying share: two tests' mean ends inside it, a third's past it
local SHARE_TESTS: number = 2
local BUDGET: number = 8.5 * SPIN -- Room for a few player tests after the share, far short of every player's
local SLEEPERS: number = 4
local PLAYERS: number = 12
local SPACING: number = 10 -- Studs between neighbors, sleepers along -X and players along +X
local LATER: number = 0.05 -- Seconds on, at the starved slice

-- The field of each kind's state that only aiming its test reads, and how many times one aim reads it
local SLOWED: { [string]: { field: string, reads: number } } = {
	Player = { field = "posture", reads = 1 },
	Sleeper = { field = "facing", reads = 2 },
}

-- A target's state whose aim holds the thread for SPIN seconds of os.clock in all, spread over its reads
local function slowed(state: any, kind: string): any
	local field: string = SLOWED[kind].field
	local spin: number = SPIN / SLOWED[kind].reads

	return setmetatable({}, {
		__index = function (_: any, key: string): any
			if key == field then
				local stop: number = os.clock() + spin
				while os.clock() < stop do
					continue
				end
			end

			return state[key]
		end,
	})
end

return function (): (boolean, string | nil)
	local override: { [string]: any } = StandIn.override()
	local Harness: any = Environment.load(HARNESS, { [POOL] = override })
	local harness: any = Harness.new(function (_: any, server: any)
		server.antiEsp.lyingShare = SHARE
		server.antiEsp.workers = WORKERS
	end)

	local AntiEsp: any = Harness.AntiEsp
	local pool: any = override.made
	pool.wall = Harness.solid

	local own: number, viewer: any = harness:player("Viewer", vector.zero)
	local targets: { number } = {}
	local kinds: { [number]: string } = {}

	for index: number = 1, SLEEPERS do
		local slot: number = harness:body("Sleeper", vector.create(-SPACING * index, 0, 0))
		table.insert(targets, slot)
		kinds[slot] = "Sleeper"
	end

	for index: number = 1, PLAYERS do
		local slot: number = harness:body("Player", vector.create(SPACING * index, 0, 0))
		table.insert(targets, slot)
		kinds[slot] = "Player"
	end

	local function ask()
		for _, target: number in targets do
			AntiEsp.isHidden(viewer, target)
		end
	end

	-- Every pair tested hidden, then all of them due at once by the viewer's own move, as a full load leaves them
	ask()
	harness:slice(0)
	ask()
	AntiEsp.moved(own)

	for _, target: number in targets do
		harness.states[target] = slowed(harness.states[target], kinds[target])
	end

	pool.wall = Harness.open
	table.clear(pool.sends)
	table.clear(pool.rays)
	harness:slice(LATER, BUDGET)

	-- No walls, so each packed pair casts its first ray alone, in the order packed, and its end's X tells the kinds
	local lyingPacked: number = 0
	local playersPacked: number = 0
	for _, ray: any in pool.rays do
		if ray.to.x > 0 then
			playersPacked += 1
		elseif playersPacked > 0 then
			return false, "A sleeper pair was packed after a player pair, inside the sleepers' share"
		else
			lyingPacked += 1
		end
	end

	local _, waiting: number = AntiEsp.lying()
	if #pool.sends ~= 1 or pool.sends[1].pairs ~= lyingPacked + playersPacked then
		return false, "The slice did not send what it packed in one batch"
	elseif lyingPacked == 0 then
		return false, `With {SLEEPERS} sleepers waiting under {PLAYERS} due players, the slice packed no sleeper`
	elseif lyingPacked > SHARE_TESTS then
		return false, `The slice packed {lyingPacked} sleepers, past the {SHARE_TESTS} whose mean ends inside the share`
	elseif waiting ~= SLEEPERS - lyingPacked then
		return false, `{lyingPacked} sleepers packed left {waiting} waiting`
	elseif playersPacked == 0 or playersPacked >= PLAYERS then
		return false, `After the sleepers' share the slice packed {playersPacked} of {PLAYERS} due players`
	end

	return true, nil
end
