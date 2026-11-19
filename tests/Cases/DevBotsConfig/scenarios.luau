--[[
    The bot harness's scenarios match the A0 arm's, S1 to S4 on its areas and
    counts, every scenario keeps to a 150-slot server's 149 bots with one name
    per group, S7 holds every cheat, and the program's timing is A0's
--]]

--!strict
local Harness = require("../../Fixtures/DevBot/Harness")

local BOTS: number = 149
local CHEATS: { string } = { "lagSwitch", "relabel", "tamper", "crouchLoss", "freeze", "longMove" }

-- A0's groups for S1 to S4: each group's count, its spawn area's center and size, and its roam area's size, 0 for none
type Expected = { count: number, x: number, z: number, size: number, depth: number, roam: number }

local A0: { [string]: { Expected } } = {
	S1 = { { count = 149, x = 0, z = 0, size = 2000, depth = 2000, roam = 0 } },
	S2 = { { count = 149, x = 0, z = 0, size = 2000, depth = 2000, roam = 2000 } },
	S3 = {
		{ count = 60, x = 3880, z = -45, size = 100, depth = 60, roam = 600 },
		{ count = 89, x = 0, z = 0, size = 2000, depth = 2000, roam = 2000 },
	},
	S4 = { { count = 149, x = 0, z = 0, size = 100, depth = 100, roam = 100 } },
}

return function (): (boolean, string | nil)
	local Config: any = Harness.load().Config

	for name: string, groups: { Expected } in A0 do
		local scenario: any = Config.scenarios[name]

		for index: number, expected: Expected in groups do
			local group: any = scenario.groups[index]
			local spawn: any = group and group.spawn
			local roam: number = group and group.roam and group.roam.size.X or 0

			local same: boolean = group ~= nil
				and group.count == expected.count
				and spawn.center.X == expected.x
				and spawn.center.Z == expected.z
				and spawn.size.X == expected.size
				and spawn.size.Y == expected.depth
				and roam == expected.roam

			if not same then
				return false, `{name}'s group {index} is not the A0 arm's`
			end
		end
	end

	for _, name: string in Config.order do
		local scenario: any = Config.scenarios[name]
		local total: number = 0
		local names: { [string]: boolean } = {}

		if scenario == nil then
			return false, `The smoke order names {name}, which no scenario is`
		end

		for _, group: any in scenario.groups do
			total += group.count

			if names[group.name] then
				return false, `{name} names two groups {group.name}, which its reports are kept by`
			end

			names[group.name] = true
		end

		if total > BOTS then
			return false, `{name} builds {total} bots, more than a 150-slot server's {BOTS}`
		end
	end

	local cheats: { [string]: boolean } = {}
	for _, group: any in Config.scenarios.S7.groups do
		if group.cheat then
			cheats[group.cheat] = true
		end
	end

	for _, cheat: string in CHEATS do
		if not cheats[cheat] then
			return false, `S7 has no group of {cheat} bots`
		end
	end

	local full: any = Config.full
	if table.concat(full.seeds, ",") ~= "1,2,3" or full.warmup ~= 30 or full.window ~= 120 then
		return false, "The benchmark program's runs are not seeds 1 to 3 with a 30 s warm-up and a 120 s window"
	end

	return true, nil
end
