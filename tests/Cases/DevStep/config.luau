--[[
    The step benchmark's block names S4 and the two spread loads in their
    halves' order with the design's timing, and every area of every load,
    moved onto the plaza spawn as a run moves it, lies inside the wire bounds
--]]

--!strict
local roblox: any = require("@lune/roblox") -- Its typedefs leave out the datatypes

local Harness = require("../../Fixtures/DevBot/Harness")

local SPAWN: any = roblox.Vector3.new(3834, 0.5, -74) -- The real player's spawn on the plaza, which a run follows
local HEIGHT: number = 0.5 -- The plaza floor's height above 0, where each landing stands

-- The loads in the order they run, each with its halves' levers in the order the halves run
local LOADS: { { scenario: string, order: string } } = {
	{ scenario = "S4", order = "false,true" },
	{ scenario = "Spread150", order = "true,false" },
	{ scenario = "Spread300", order = "false,true" },
}

-- Each place a run's follow can land its viewer point: the spawn and each corner of the plaza's spawn area
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

	-- 1) The session, the drift share, the loads in their order, and the design's timing
	if step.session ~= 1 then
		return false, `The step benchmark flips session {step.session}'s levers, not session 1's`
	elseif step.drift ~= 0.05 then
		return false, `The table flags a drift past {step.drift}, not 5%`
	elseif #step.loads ~= #LOADS then
		return false, `The step benchmark runs {#step.loads} loads, not {#LOADS}`
	end

	for index: number, expected: { scenario: string, order: string } in LOADS do
		local load: any = step.loads[index]
		local order: { string } = {}
		for _, on: boolean in load.order do
			table.insert(order, tostring(on))
		end

		if load.scenario ~= expected.scenario or table.concat(order, ",") ~= expected.order then
			return false, `Load {index} is {load.scenario} with its halves {table.concat(order, ",")}`
		elseif Config.scenarios[load.scenario] == nil then
			return false, `The step benchmark runs {load.scenario}, which no scenario is`
		end
	end

	local timing: any = step.timing
	if table.concat(timing.seeds, ",") ~= "1" or timing.warmup ~= 10 or timing.window ~= 50 or timing.interval ~= 1 then
		return false, "The step benchmark's timing is not one seed of a 10 s warm-up and a 50 s window"
	end

	-- 2) Each area, its floor's margin and a body's lift included, inside the bounds wherever the follow lands it
	local bound: number = Constants.PLAY_BOUND
	local margin: number = Config.spawn.margin
	local lift: number = Config.spawn.lift
	local plaza: any = Config.scenarios.S3.groups[1].spawn

	for _, load: any in step.loads do
		local scenario: any = Config.scenarios[load.scenario]
		if scenario.follow ~= true then
			return false, `{load.scenario} does not follow the real player, so its areas stay where the config has them`
		end

		for _, landing: any in landings(plaza) do
			local offset: any = landing - scenario.viewer

			for _, group: any in scenario.groups do
				for _, area: any in { group.spawn, group.roam } do
					local center: any = area.center + offset
					local reachX: number = math.abs(center.X) + area.size.X / 2 + margin
					local reachZ: number = math.abs(center.Z) + area.size.Y / 2 + margin
					local height: number = center.Y + lift

					if reachX > bound or reachZ > bound then
						return false, `{load.scenario}'s {group.name} area reaches {reachX}, {reachZ} studs at {center}`
					elseif height < Constants.HEIGHT_MIN or height > Constants.HEIGHT_MAX then
						return false, `{load.scenario}'s {group.name} bodies stand at {height} studs at {center}`
					end
				end
			end
		end
	end

	return true, nil
end
