--[[
    The gates' loads hold the bodies and areas their benchmarks name, with
    every NPC and sleeper group after each bot group, S9's 2,000 sleepers
    split at the estimate's density, each listed in gates, order unchanged
--]]

--!strict
local Harness = require("../../Fixtures/DevBot/Harness")

local ORDER: string = "S0,S1,S2,S3,S4,S5,S6,S7"
local GATES: string = "S3Npcs,S4Npcs,S9,S10,G10,G10Rung2,G5"
local SLEEPERS: number = 2000
local RADIUS: number = 500 -- The sleepers' reveal radius, the estimate's density counted within it
local DENSITY: { number } = { 50, 51 } -- The spread sleepers a map viewer has within it, about 50.5
local ISLAND: number = 3048 -- Studs from 0 to the island's edge, which every spread sleeper lies inside

-- An area as the config holds one, its center's X and Z and its width and depth
local function at(x: number, z: number, width: number, depth: number): any
	return { center = { X = x, Z = z }, size = { X = width, Y = depth } }
end

local MAP: any = at(0, 0, 2000, 2000)
local CITY: any = at(3900, 0, 600, 600)
local PLAZA: any = at(3880, -45, 100, 60)
local FIGHT: any = at(0, 0, 100, 100)
local SPREAD: any = at(0, 0, 5400, 5400)

-- Each load's groups in build order, and whether its areas follow the first real player
type Expected = { follow: boolean, groups: { any } }

local EXPECTED: { [string]: Expected } = {
	S3Npcs = {
		follow = false,
		groups = {
			{ count = 60, spawn = PLAZA, roam = CITY },
			{ count = 89, spawn = MAP, roam = MAP },
			{ kind = "npc", count = 32, spawn = PLAZA, roam = CITY },
		},
	},
	S4Npcs = {
		follow = true,
		groups = {
			{ count = 149, spawn = FIGHT, roam = FIGHT },
			{ kind = "npc", count = 32, spawn = FIGHT, roam = FIGHT },
		},
	},
	S9 = {
		follow = false,
		groups = {
			{ count = 60, spawn = PLAZA, roam = CITY },
			{ count = 89, spawn = MAP, roam = MAP },
			{ kind = "sleeper", count = 125, spawn = CITY },
			{ kind = "sleeper", count = 1875, spawn = SPREAD },
		},
	},
	S10 = {
		follow = false,
		groups = {
			{ count = 60, spawn = PLAZA, roam = CITY },
			{ count = 85, spawn = MAP, roam = MAP },
			{ count = 4, spawn = PLAZA, spectate = "city" },
		},
	},
	G10 = {
		follow = true,
		groups = {
			{ count = 299, spawn = MAP, roam = MAP },
			{ kind = "npc", count = 32, spawn = MAP, roam = MAP },
		},
	},
	G10Rung2 = {
		follow = true,
		groups = {
			{ count = 299, spawn = MAP, roam = MAP },
			{ kind = "npc", count = 32, spawn = MAP, roam = MAP, awake = false },
		},
	},
	G5 = { follow = true, groups = { { count = 149, spawn = FIGHT, roam = FIGHT, team = 1 } } },
}

-- An area as one line, nowhere for none
local function area(value: any): string
	if value == nil then
		return "nowhere"
	end

	return `{value.center.X},{value.center.Z} {value.size.X}x{value.size.Y}`
end

-- A group as one line of what its load builds
local function describe(group: any): string
	local kind: string = `{group.kind or "bot"} {group.count}`
	local where: string = `at {area(group.spawn)} roaming {area(group.roam)}`
	local how: string = `awake {group.awake}, spectating {group.spectate}, team {group.team}, sprint {group.sprint}`

	return `{kind} {where}, {how}`
end

return function (): (boolean, string | nil)
	local loaded: Harness.Loaded = Harness.load()
	local Config: any = loaded.Config

	if table.concat(Config.order, ",") ~= ORDER then
		return false, `The smoke order is {table.concat(Config.order, ",")}, not {ORDER}`
	elseif table.concat(Config.gates, ",") ~= GATES then
		return false, `The gates' loads are {table.concat(Config.gates, ",")}, not {GATES}`
	end

	for name: string, expected: Expected in EXPECTED do
		local scenario: any = Config.scenarios[name]
		if scenario == nil then
			return false, `No scenario is named {name}`
		elseif scenario.follow ~= expected.follow or #scenario.groups ~= #expected.groups then
			return false, `{name} has {#scenario.groups} groups and follow {scenario.follow}, not its load's`
		end

		local names: { [string]: boolean } = {}
		for index: number, group: any in scenario.groups do
			local want: string = describe(expected.groups[index])
			local got: string = describe(group)

			if got ~= want then
				return false, `{name}'s group {index} is {got}, not {want}`
			elseif names[group.name] then
				return false, `{name} names two groups {group.name}, which its lines are kept by`
			end

			names[group.name] = true
		end
	end

	-- Every scenario builds its bots before any NPC or sleeper, so a seed's bots walk as its load without them does
	for name: string, scenario: any in Config.scenarios do
		local bodies: boolean = false
		for _, group: any in scenario.groups do
			if group.kind ~= nil then
				bodies = true
			elseif bodies then
				return false, `{name}'s bot group {group.name} comes after an NPC or sleeper group`
			end
		end
	end

	-- Every load's areas inside the wire's bound across, which positions are stored to
	local bound: number = loaded.Constants.PLAY_BOUND
	for _, name: string in Config.gates do
		for _, group: any in Config.scenarios[name].groups do
			for _, value: any in { group.spawn, group.roam } do
				local reach: number =
					math.max(math.abs(value.center.X) + value.size.X / 2, math.abs(value.center.Z) + value.size.Y / 2)

				if reach > bound then
					return false, `{name}'s group {group.name} reaches {reach} studs from 0, past the bound {bound}`
				end
			end
		end
	end

	local city: any = Config.scenarios.S9.groups[3]
	local spread: any = Config.scenarios.S9.groups[4]
	local size: any = spread.spawn.size
	local near: number = spread.count / (size.X * size.Y) * math.pi * RADIUS ^ 2

	if city.count + spread.count ~= SLEEPERS then
		return false, `S9 lays {city.count + spread.count} sleepers, not {SLEEPERS}`
	elseif not (near >= DENSITY[1] and near <= DENSITY[2]) then
		return false, `S9's spread sleepers give a map viewer {near} within {RADIUS} studs, not about 50.5`
	elseif size.X / 2 > ISLAND or size.Y / 2 > ISLAND then
		return false, `S9's spread sleepers reach past the island's edge at {ISLAND} studs`
	end

	return true, nil
end
