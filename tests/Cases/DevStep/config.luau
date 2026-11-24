--[[
    The step benchmark's block flips step 3's levers over S4 and the spread
    loads in their halves' order with the design's timing, its NPC and levers
    runs' loads beside them, every area inside the bounds and clear box
--]]

--!strict
local roblox: any = require("@lune/roblox") -- Its typedefs leave out the datatypes

local Harness = require("../../Fixtures/DevBot/Harness")

local SPAWN: any = roblox.Vector3.new(3834, 0.5, -74) -- The real player's spawn on the plaza, where a half stands
local HEIGHT: number = 0.5 -- The plaza floor's height above 0, where each landing stands

-- The loads in the order they run, each with its halves' levers in the order the halves run and any lever it flips
type Load = { scenario: string, order: string, lever: string? }

local LOADS: { Load } = {
	{ scenario = "S4", order = "false,true" },
	{ scenario = "Spread150", order = "true,false" },
	{ scenario = "Spread300", order = "false,true" },
}

-- The NPC budget run's one load, and the levers run's, each flipping one of session 2's levers alone
local NPCS: Load = { scenario = "S4Npcs", order = "false,true" }
local LEVERS: { Load } = {
	{ scenario = "S4", order = "false,true", lever = "crowdCap" },
	{ scenario = "S4", order = "true,false", lever = "antiEspWorkers" },
	{ scenario = "Spread300", order = "false,true", lever = "bands" },
}

-- Whether a configured load is the one expected, or why not
local function differs(load: any, expected: Load, Config: any): string?
	local order: { string } = {}
	for _, on: boolean in load.order do
		table.insert(order, tostring(on))
	end

	if load.scenario ~= expected.scenario or table.concat(order, ",") ~= expected.order then
		return `{load.scenario} with its halves {table.concat(order, ",")}`
	elseif load.lever ~= expected.lever then
		return `{load.scenario} flipping {load.lever}, not {expected.lever}`
	elseif Config.scenarios[load.scenario] == nil then
		return `{load.scenario}, which no scenario is`
	end

	return nil
end

-- Step 1's near and far tiers as the before half's two bands, each aim/floor in Hz, and their one edge, enter/leave
local BEFORE_BANDS: string = "20/15,15/10"
local BEFORE_EDGES: string = "200/220"

-- Each place a half can land its viewer point, whose spawn grid the place's attributes lay: the spawn and each corner
-- of the plaza's spawn area
local function landings(plaza: any): { any }
	local found: { any } = { SPAWN }
	for _, x: number in { -1, 1 } do
		for _, z: number in { -1, 1 } do
			local corner: any = plaza.center + roblox.Vector3.new(x * plaza.size.X / 2, 0, z * plaza.size.Y / 2)
			table.insert(found, roblox.Vector3.new(corner.X, HEIGHT, corner.Z))
		end
	end

	return found
end

return function (): (boolean, string | nil)
	local harness: Harness.Loaded = Harness.load()
	local Config: any = harness.Config
	local Constants: any = harness.Constants
	local step: any = Config.step

	-- 1) The session, the before half's bands, the drift share, the loads in their order, and the design's timing
	local bands: { string } = {}
	for _, band: any in step.before.bands do
		table.insert(bands, `{band.aim}/{band.floor}`)
	end

	local edges: { string } = {}
	for _, edge: any in step.before.edges do
		table.insert(edges, `{edge.enter}/{edge.leave}`)
	end

	if step.session ~= 3 then
		return false, `The step benchmark flips session {step.session}'s levers, not session 3's`
	elseif table.concat(bands, ",") ~= BEFORE_BANDS or table.concat(edges, ",") ~= BEFORE_EDGES then
		return false, `The before half's bands are {table.concat(bands, ",")} with edges {table.concat(edges, ",")}`
	elseif step.drift ~= 0.05 then
		return false, `The table flags a drift past {step.drift}, not 5%`
	elseif #step.loads ~= #LOADS then
		return false, `The step benchmark runs {#step.loads} loads, not {#LOADS}`
	elseif #step.levers ~= #LEVERS then
		return false, `The levers run runs {#step.levers} loads, not {#LEVERS}`
	end

	for index: number, expected: Load in LOADS do
		local problem: string? = differs(step.loads[index], expected, Config)
		if problem then
			return false, `Load {index} is {problem}`
		end
	end

	local npcs: string? = differs(step.npcs, NPCS, Config)
	if npcs then
		return false, `The NPC budget run's load is {npcs}`
	end

	for index: number, expected: Load in LEVERS do
		local problem: string? = differs(step.levers[index], expected, Config)
		if problem then
			return false, `The levers run's load {index} is {problem}`
		end
	end

	local timing: any = step.timing
	if table.concat(timing.seeds, ",") ~= "1" or timing.warmup ~= 10 or timing.window ~= 50 or timing.interval ~= 1 then
		return false, "The step benchmark's timing is not one seed of a 10 s warm-up and a 50 s window"
	end

	-- 2) Each area of every run's loads, its floor's margin and a body's lift included, inside the bounds and the
	-- island copy's clear box, S9's spread square on the same landing, wherever a half lands it
	local bound: number = Constants.PLAY_BOUND
	local margin: number = Config.spawn.margin
	local lift: number = Config.spawn.lift
	local plaza: any = Config.scenarios.S3.groups[1].spawn
	local clear: any = Config.scenarios.S9.groups[4].spawn.size / 2
	local every: { any } = table.clone(step.loads)
	table.insert(every, step.npcs)
	table.move(step.levers, 1, #step.levers, #every + 1, every)

	for _, load: any in every do
		local scenario: any = Config.scenarios[load.scenario]
		if scenario.follow ~= true then
			return false, `{load.scenario} follows no one, so its half's areas stay where the config has them`
		end

		for _, landing: any in landings(plaza) do
			local offset: any = landing - scenario.viewer

			for _, group: any in scenario.groups do
				for _, area: any in { group.spawn, group.roam } do
					local center: any = area.center + offset
					local reachX: number = math.abs(center.X) + area.size.X / 2 + margin
					local reachZ: number = math.abs(center.Z) + area.size.Y / 2 + margin
					local height: number = center.Y + lift
					local outX: number = math.abs(center.X - landing.X) + area.size.X / 2 + margin
					local outZ: number = math.abs(center.Z - landing.Z) + area.size.Y / 2 + margin

					if reachX > bound or reachZ > bound then
						return false, `{load.scenario}'s {group.name} area reaches {reachX}, {reachZ} studs at {center}`
					elseif height < Constants.HEIGHT_MIN or height > Constants.HEIGHT_MAX then
						return false, `{load.scenario}'s {group.name} bodies stand at {height} studs at {center}`
					elseif outX > clear.X or outZ > clear.Y then
						return false,
							`{load.scenario}'s {group.name} area reaches {outX}, {outZ} studs past the clear box`
					end
				end
			end
		end
	end

	return true, nil
end
