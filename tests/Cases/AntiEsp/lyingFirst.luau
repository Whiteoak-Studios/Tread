--[[
    With the lying share set to the whole slice, a slice tests every waiting
    sleeper and body pair before any player pair and gives the players the
    time they leave, and with none waiting gives the players the whole slice
--]]

--!strict
local Environment = require("../../Environment")

local HARNESS: string = "tests/Fixtures/AntiEsp/Harness.luau"
local BUDGET: number = 1 -- Seconds, the slice and its lying share, more than every due test needs
local SLEEPERS: number = 2
local BODIES: number = 1
local PLAYERS: number = 4
local SPACING: number = 10 -- Studs between neighbors, lying bodies along -X and players along +X
local FIRST: number = 0.05 -- Seconds on, at the slice with sleepers and bodies waiting
local SECOND: number = 0.1 -- And at the one with none, before any visible pair's recheck

return function (): (boolean, string | nil)
	local Harness: any = Environment.load(HARNESS)
	local harness: any = Harness.new(function (_: any, server: any)
		server.antiEsp.lyingShare = BUDGET
	end)
	local AntiEsp: any = Harness.AntiEsp

	local own: number, viewer: any = harness:player("Viewer", vector.zero)
	local players: { number } = {}
	local targets: { number } = {}

	for index: number = 1, SLEEPERS + BODIES do
		local kind: string = index > SLEEPERS and "Body" or "Sleeper"
		table.insert(targets, harness:body(kind, vector.create(-SPACING * index, 0, 0)))
	end

	for index: number = 1, PLAYERS do
		local slot: number = harness:body("Player", vector.create(SPACING * index, 0, 0))
		table.insert(players, slot)
		table.insert(targets, slot)
	end

	local function ask()
		for _, target: number in targets do
			AntiEsp.isHidden(viewer, target)
		end
	end

	-- Every pair tested once and seen, then all due again by the viewer's own move; each test casts its first ray
	ask()
	harness:slice(0)
	ask()
	AntiEsp.moved(own)
	harness:slice(FIRST, BUDGET)

	local lyingRays: number = 0
	local playerRays: number = 0
	for _, ray: any in harness.rays do
		if ray.to.x > 0 then
			playerRays += 1
		elseif playerRays > 0 then
			return false, "A sleeper or body pair was tested after a player pair"
		else
			lyingRays += 1
		end
	end

	if lyingRays ~= SLEEPERS + BODIES or playerRays ~= PLAYERS then
		local cast: string = `{lyingRays} lying rays and {playerRays} player rays`
		return false, `The slice with every pair due cast {cast}, not {SLEEPERS + BODIES} and {PLAYERS}`
	end

	-- The players alone due: the share keeps nothing back while no sleeper or body waits
	ask()
	for _, slot: number in players do
		AntiEsp.moved(slot)
	end

	harness:slice(SECOND, BUDGET)

	local _, waiting: number = AntiEsp.lying()
	if waiting ~= 0 then
		return false, `{waiting} sleeper or body pairs waited with none made due`
	elseif #harness.rays ~= PLAYERS then
		return false, `With no sleeper or body waiting, the slice tested {#harness.rays} of {PLAYERS} due players`
	end

	return true, nil
end
