--[[
    A teleport ends a crouch slide as every end but leaving the ground does,
    starting the slide's cooldown in whole ticks, while a walking body's
    teleport leaves its cooldown at 0
--]]

--!strict
local roblox: any = require("@lune/roblox") -- Its typedefs leave out the datatypes

local Intake = require("../../Fixtures/Commands/Intake")

local SLIDING: number = 7 -- The sliding character's slot
local WALKING: number = 8 -- The walking one's
local LIFT: number = 0.5 -- Studs over the fixture floor each destination is, clear of it

return function (): (boolean, string | nil)
	local rig: Intake.Intake = Intake.new()
	local dataModel: any = rig.globals.game
	local tread: any = dataModel:GetService("ReplicatedStorage").Packages.Tread
	local fixtures: any = dataModel:GetService("ServerScriptService").Fixtures
	local Slides: any = rig.globals.require(fixtures.Step.Slides)
	local Teleport: any = rig.globals.require(tread.Server.Teleport)
	local Range: any = rig.globals.require(tread.Server.Range)
	local server: any = rig.globals.require(fixtures.Config.Example).server()

	local world: any = Slides.world()
	local cooldown: number = math.round(world.settings.slide.cooldown / world.delta)
	Teleport.start({ shared = rig.shared, server = server }, world)

	-- One body mid-slide and one walking, each on the slide fixture's floor
	local slider: any = Slides.state(vector.create(0, Slides.resting, 100), true)
	slider.mode = "Slide"
	slider.posture = "Crouch"
	slider.velocity = vector.create(0, 0, -18)

	local walker: any = Slides.state(vector.create(20, Slides.resting, 100), true)
	walker.velocity = vector.create(0, 0, -10)

	local sliding: any = { player = rig.bot, _slot = SLIDING, _generation = 1, _live = true }
	local walking: any = { player = rig.bot, _slot = WALKING, _generation = 1, _live = true }
	Range.set(SLIDING, slider.position, rig.bot.Name)
	Range.set(WALKING, walker.position, rig.bot.Name)

	Teleport.run(1)
	Teleport.schedule(sliding, roblox.CFrame.new(-10, Slides.floor + LIFT, 60), slider, rig.connection)
	Teleport.schedule(walking, roblox.CFrame.new(30, Slides.floor + LIFT, 60), walker, rig.connection)

	-- A bot's destination is ready at once, and the move lands on the run after the call
	Teleport.run(1)
	Teleport.run(2)

	if slider.position.z ~= 60 or walker.position.z ~= 60 then
		return false, `The bodies stood at {slider.position} and {walker.position}, not at their destinations`
	elseif slider.mode ~= "Air" or slider.slideCooldown ~= cooldown then
		return false, `The teleported slide was left in {slider.mode} with a cooldown of {slider.slideCooldown}`
	elseif walker.mode ~= "Air" or walker.slideCooldown ~= 0 then
		return false, `The teleported walk was left in {walker.mode} with a cooldown of {walker.slideCooldown}`
	end

	return true, nil
end
