--[[
    The sampler's cap: a cap that is no whole number of boxes refused, the
    boxes past it dropped and counted, and the recording holding exactly the
    kept ones, the first walkers', a cap of 0 keeping none
--]]

--!strict
local Harness = require("../../Fixtures/DevServer/Harness")
local Kit = require("../../Fixtures/Exploits/Kit")

local SETTLES: string = "dev/Server/Parallel/Settles.luau"
local CAP: number = 2
local MOVES: number = 4 -- Walking steps past the seeding read, two more than the cap keeps
local REFUSED: { number } = { -1, 1.5 }
local WHOLE: string = "whole number of boxes" -- What the refusal says a cap must be

-- The step block's keys the box reads
local SETTINGS: { [string]: number } = { radius = 1.25, standing = 5, crouched = 3 }

-- A walker seeded at x 0 and stepped a stud along x on each of the ticks after, gathering any error a read threw
local function walk(Settles: any, State: any, sampler: any, moves: number): string?
	local state: any = State.new()
	for move: number = 0, moves do
		state.tick = move
		state.position = vector.create(move, 3, 0)

		local read: boolean, failure: any = pcall(Settles.read, sampler, "walker", state)
		if not read then
			return `the read on tick {move} threw: {failure}`
		end
	end

	return nil
end

return function (): (boolean, string | nil)
	local loaded: Harness.Loaded = Harness.load()
	local dataModel: any = loaded.game
	local server: any = dataModel:GetService("ServerScriptService").Server
	local packages: any = dataModel:GetService("ReplicatedStorage").Packages
	local State: any = loaded.require(packages.Tread.Step.State)
	local Queries: any = loaded.require(server.Parallel.Queries)

	-- Characters and the bot harness's runs stand in empty, since the case hands each read its state
	local results: { [any]: any } = { [packages.Tread.Server.Characters] = {}, [server.Bots.Run] = {} }
	local Settles: any =
		Kit.loader(dataModel, { [server.Parallel.Settles] = SETTLES }, results, loaded.require)(server.Parallel.Settles)

	-- 1) A cap below 0 or between whole numbers is refused
	for _, cap: number in REFUSED do
		local made: boolean, failure: any = pcall(Settles.new, "Case", cap, SETTINGS)
		if made or not tostring(failure):find(WHOLE, 1, true) then
			return false, `A cap of {cap} made a sampler: {made}, its error {failure}`
		end
	end

	-- 2) Past the cap each walking box is dropped and counted, never written
	local sampler: any = Settles.new("Case", CAP, SETTINGS)
	local thrown: string? = walk(Settles, State, sampler, MOVES)
	if thrown then
		return false, `Walking past the cap of {CAP}: {thrown}`
	end

	local recording: any = Settles.recording(sampler)
	local counts: string = `{recording.walkers} walkers, {recording.recorded} recorded, {recording.dropped} dropped`
	if counts ~= `{MOVES} walkers, {CAP} recorded, {MOVES - CAP} dropped` then
		return false, `{MOVES} walking steps under a cap of {CAP} counted {counts}`
	end

	-- 3) The recording holds exactly the kept boxes, the first two walkers' at x 1 and 2
	local bytes: number = CAP * Queries.BOX_WIDTH * Queries.VALUE_BYTES
	if buffer.len(recording.boxes) ~= bytes then
		return false, `The recording of {CAP} boxes took {buffer.len(recording.boxes)} B, not {bytes}`
	end

	local xs: { number } = {}
	Queries.overlaps(recording.boxes, function (center: vector, _: vector): boolean
		table.insert(xs, center.x)

		return false
	end)

	if table.concat(xs, " ") ~= "1 2" then
		return false, `The kept boxes stood at x {table.concat(xs, " ")}, not 1 and 2`
	end

	-- 4) A cap of 0 keeps nothing and drops every walking box
	local none: any = Settles.new("Case", 0, SETTINGS)
	thrown = walk(Settles, State, none, 1)
	if thrown then
		return false, `Walking under a cap of 0: {thrown}`
	end

	local empty: any = Settles.recording(none)
	if empty.recorded ~= 0 or empty.dropped ~= 1 or buffer.len(empty.boxes) ~= 0 then
		return false, `A cap of 0 recorded {empty.recorded} and dropped {empty.dropped} in {buffer.len(empty.boxes)} B`
	end

	return true, nil
end
