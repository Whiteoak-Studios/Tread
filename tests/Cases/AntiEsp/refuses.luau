--[[
    Anti-ESP refuses what it can't take: any member before start, starting
    twice, without its tables or blocked, or with more rays than a test
    has in any posture's aim or the sleepers', a budget or clock that is no
    finite number, a value that is no slot, a team that is no number, and
    leaving with no key
--]]

--!strict
local Environment = require("../../Environment")
local Refuses = require("../../Fixtures/Codec/Refuses")

local ANTI_ESP: string = "src/Server/AntiEsp.luau"
local EXAMPLE: string = "tests/Fixtures/Config/Example.luau"
local HARNESS: string = "tests/Fixtures/AntiEsp/Harness.luau"
local NOT_SLOTS: { number } = { -1, 4096, 1.5 }
local NOT_NUMBERS: { any } = { -1, 0 / 0, math.huge, "soon" }
local POSTURES: { string } = { "Stand", "Crouch", "Downed" }

local function blocked(_: vector, _: vector): boolean
	return false
end

return function (): (boolean, string | nil)
	local AntiEsp: any = Environment.load(ANTI_ESP)
	local viewer: any = { key = { Name = "Viewer" }, position = vector.zero, acknowledged = 0, received = 0 }

	local early: { { any } } = {
		{ "run", 0.002, 0 },
		{ "isHidden", viewer, 0 },
		{ "setTeam", 0, 1 },
		{ "moved", 0 },
		{ "leave", viewer.key },
		{ "aimPoints", vector.zero, {} },
	}

	for _, row: { any } in early do
		local refused: boolean, why: string = Refuses("before AntiEsp.start", AntiEsp[row[1]], row[2], row[3])
		if not refused then
			return false, `AntiEsp.{row[1]} before start went another way: {why}`
		end
	end

	-- Each start below fails before it starts anything, so the next one still runs
	local Example: any = Environment.load(EXAMPLE)
	local settings: any = { shared = Example.shared(), server = Example.server() }
	local world: any = {}
	local starts: { { any } } = {
		{ "no settings table", "as tables", nil, world, {}, blocked },
		{ "no states table", "as tables", settings, world, nil, blocked },
		{ "no blocked function", "blocked as a function", settings, world, {}, "walls" },
	}

	for _, row: { any } in starts do
		local refused: boolean, why: string = Refuses(row[2], AntiEsp.start, row[3], row[4], row[5], row[6])
		if not refused then
			return false, `AntiEsp.start with {row[1]} went another way: {why}`
		end
	end

	local refused: boolean, why: string

	-- A seventh point in each posture's list, taken away again before the next
	for _, posture: string in POSTURES do
		local points: { any } = settings.server.antiEsp.aim[posture]
		table.insert(points, { up = 2, side = 0 })

		refused, why = Refuses(`antiEsp.aim.{posture} is at most the 6`, AntiEsp.start, settings, world, {}, blocked)
		if not refused then
			return false, `AntiEsp.start with 7 {posture} points went another way: {why}`
		end

		table.remove(points)
	end

	settings.server.sleepers.rays = 4
	refused, why = Refuses("sleepers.rays is at most the 3", AntiEsp.start, settings, world, {}, blocked)
	if not refused then
		return false, `AntiEsp.start with 4 rays a sleeper went another way: {why}`
	end

	-- Started through the harness from here on
	local Harness: any = Environment.load(HARNESS)
	local harness: any = Harness.new()
	AntiEsp = Harness.AntiEsp

	refused, why = Refuses("runs once", AntiEsp.start, settings, world, {}, blocked)
	if not refused then
		return false, `A second AntiEsp.start went another way: {why}`
	end

	for _, value: any in NOT_NUMBERS do
		refused, why = Refuses("a budget in seconds", AntiEsp.run, value, 0)
		if not refused then
			return false, `AntiEsp.run with a budget of {value} went another way: {why}`
		end
	end

	for _, value: any in { 0 / 0, math.huge, -math.huge, "soon" } do
		refused, why = Refuses("the schedule's clock", AntiEsp.run, 0.002, value)
		if not refused then
			return false, `AntiEsp.run at {value} went another way: {why}`
		end
	end

	local slot: number, own: any = harness:player("Own", vector.zero)
	for _, value: number in NOT_SLOTS do
		for _, member: string in { "moved", "setTeam" } do
			refused, why = Refuses("one of the slot table's slots", AntiEsp[member], value, nil)
			if not refused then
				return false, `AntiEsp.{member} of {value} went another way: {why}`
			end
		end

		refused, why = Refuses("Slots.get takes a slot", AntiEsp.isHidden, own, value)
		if not refused then
			return false, `AntiEsp.isHidden of {value} went another way: {why}`
		end
	end

	for _, team: any in { "red", 0 / 0, {} } do
		refused, why = Refuses("a team as a number or nil", AntiEsp.setTeam, slot, team)
		if not refused then
			return false, `AntiEsp.setTeam to {team} went another way: {why}`
		end
	end

	refused, why = Refuses("the player or bot that left", AntiEsp.leave, nil)
	if not refused then
		return false, `AntiEsp.leave of nil went another way: {why}`
	end

	return true, nil
end
