--[[
    A pool refuses a template it can't build rigs from, a joints map, an
    animations map or joint limits with one missing, and a draw distance or
    collision that is none, each naming what is missing
--]]

--!strict
local roblox: any = require("@lune/roblox") -- Its typedefs leave out the datatypes

local Environment = require("../../Environment")

local RIGS: string = "src/Client/Rigs/init.luau"
local RIG: string = "tests/Fixtures/Rigs/Rig.luau"

type Trial = { name: string, says: string, spoil: (settings: any) -> () }

local TRIALS: { Trial } = {
	{
		name = "a template whose LeftKnee joint is gone",
		says = "LeftKnee",
		spoil = function (settings: any)
			settings.rig:FindFirstChild("LeftKnee", true):Destroy()
		end,
	},
	{
		name = "a joints map with no Neck",
		says = "Neck",
		spoil = function (settings: any)
			settings.joints = table.clone(settings.joints)
			settings.joints.Neck = nil
		end,
	},
	{
		name = "an animations map with no crawl",
		says = "crawl",
		spoil = function (settings: any)
			settings.animations.crawl = nil
		end,
	},
	{
		name = "joint limits with none for RightAnkle",
		says = "RightAnkle",
		spoil = function (settings: any)
			settings.bodies = table.clone(settings.bodies)
			settings.bodies.jointLimits = table.clone(settings.bodies.jointLimits)
			settings.bodies.jointLimits.RightAnkle = nil
		end,
	},
	{
		name = "a template with no PrimaryPart",
		says = "PrimaryPart",
		spoil = function (settings: any)
			settings.rig = roblox.Instance.new("Model")
		end,
	},
	{
		name = "a template that is not Archivable",
		says = "Archivable",
		spoil = function (settings: any)
			settings.rig.Archivable = false
		end,
	},
	{
		name = "a template with no AnimationController",
		says = "AnimationController",
		spoil = function (settings: any)
			settings.rig:FindFirstChildOfClass("AnimationController"):Destroy()
		end,
	},
}

return function (): (boolean, string | nil)
	local Rigs = Environment.load(RIGS)
	local Rig = Environment.load(RIG)

	for _, trial: Trial in TRIALS do
		local settings: any = Rig.settings({})
		trial.spoil(settings)

		local made: boolean, problem: any = pcall(Rigs.new, settings, Rig.drawDistance, Rig.collision())
		if made then
			return false, `Rigs.new took {trial.name}`
		elseif not tostring(problem):find(trial.says, 1, true) then
			return false, `Rigs.new refused {trial.name} without naming {trial.says}: {problem}`
		end
	end

	local distances: { any } = { 0, -1, "far" }
	for _, distance: any in distances do
		local made: boolean = pcall(Rigs.new, Rig.settings({}), distance, Rig.collision())
		if made then
			return false, `Rigs.new took {distance} as a draw distance`
		end
	end

	local madeBare: boolean = pcall(Rigs.new, Rig.settings({}), Rig.drawDistance, nil)
	if madeBare then
		return false, "Rigs.new took no collision"
	end

	local made: boolean, result: any = pcall(Rigs.new, Rig.settings({}), Rig.drawDistance, Rig.collision())
	if not made then
		return false, `Rigs.new refused the fixture's own settings: {result}`
	end

	result:destroy()

	return true, nil
end
