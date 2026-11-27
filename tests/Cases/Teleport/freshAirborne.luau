--[[
    A landing leaves a fresh airborne body, off the ground with both timers at
    0: a jump pressed on its first step in mid-air is refused, and touching
    down counts as a landing only after the game's landing airtime
--]]

--!strict
local roblox: any = require("@lune/roblox") -- Its typedefs leave out the datatypes

local Intake = require("../../Fixtures/Commands/Intake")

local GROUNDED_SLOT: number = 100
local FALLING_SLOT: number = 101
local HIGH: number = 10 -- Studs over the floor the mid-air destinations are, a fall longer than the landing airtime
local LIFT: number = 0.5 -- Studs over the floor the low destination is, a fall shorter than it
local GROUND_TICKS: number = 20 -- Ticks the grounded body has stood before its teleport
local AIR_TICKS: number = 40 -- Ticks the falling body has fallen before its teleport
local FALL_SPEED: number = -30 -- Studs a second the falling body falls at before its teleport
local FALL_LIMIT: number = 60 -- Steps a fall may take before the case fails it

return function (): (boolean, string | nil)
	local rig: Intake.Intake = Intake.new()
	local dataModel: any = rig.globals.game
	local tread: any = dataModel:GetService("ReplicatedStorage").Packages.Tread
	local fixtures: any = dataModel:GetService("ServerScriptService").Fixtures
	local Scene: any = rig.globals.require(fixtures.Step.Scene)
	local Geometry: any = rig.globals.require(fixtures.Step.Geometry)
	local casts: any = rig.globals.require(fixtures.Step.Collision)
	local Teleport: any = rig.globals.require(tread.Server.Teleport)
	local Step: any = rig.globals.require(tread.Step)
	local Command: any = rig.globals.require(tread.Codec.Command)
	local server: any = rig.globals.require(fixtures.Config.Example).server()

	local world: any = Scene.world(casts(Geometry.parts))
	Teleport.start({ shared = rig.shared, server = server }, world)

	local floor: number = Geometry.floor
	local airtime: number = math.round(Scene.settings.landing / world.delta)
	if AIR_TICKS <= airtime then
		return false, `The falling body's {AIR_TICKS} ticks no longer pass the {airtime}-tick landing airtime`
	end

	-- Steps a body with no input until it stands, giving the steps taken and the speed of any landing that counted
	local idle: any = Command.new()
	local function fall(state: any): (number, number)
		for step: number = 1, FALL_LIMIT do
			idle.number = step
			local speed: number = Step.advance(state, idle, world)
			if state.grounded then
				return step, speed
			end
		end

		return FALL_LIMIT + 1, 0
	end

	-- 1) A body that has stood a while, set down in mid-air
	local grounded: any = Scene.state(vector.create(0, floor, 0), true)
	grounded.groundTicks = GROUND_TICKS

	local standing: any = { player = rig.bot, _slot = GROUNDED_SLOT, _generation = 1, _live = true }
	Teleport.run(1)
	Teleport.schedule(standing, roblox.CFrame.new(-15, floor + HIGH, 15), grounded, rig.connection)
	Teleport.run(2)

	if grounded.grounded then
		return false, "A grounded body set down in mid-air still counted as grounded"
	elseif grounded.airTicks ~= 0 or grounded.groundTicks ~= 0 then
		return false, `The landing kept {grounded.airTicks} air ticks and {grounded.groundTicks} ground ticks`
	end

	-- Its first step presses jump, which only ground or a ladder permits
	local jump: any = Command.new()
	jump.number = 1
	jump.jump = true
	jump.pressed.jump = true

	local jumps: number = grounded.jumps
	Step.advance(grounded, jump, world)
	if grounded.jumps ~= jumps or grounded.velocity.y > 0 then
		return false, `A jump in mid-air was permitted on the step after the landing, rising at {grounded.velocity.y}`
	end

	-- 2) A body that has fallen well past the landing airtime, set down just over the floor
	local falling: any = Scene.state(vector.create(0, floor + HIGH, 0), false)
	falling.velocity = vector.create(0, FALL_SPEED, 0)
	falling.airTicks = AIR_TICKS

	local faller: any = { player = rig.bot, _slot = FALLING_SLOT, _generation = 1, _live = true }
	Teleport.schedule(faller, roblox.CFrame.new(15, floor + LIFT, -15), falling, rig.connection)
	Teleport.run(3)

	local lands: number = falling.lands
	local steps: number, speed: number = fall(falling)
	if steps > FALL_LIMIT then
		return false, `The body set down over the floor had not stood after {FALL_LIMIT} steps`
	elseif speed ~= 0 or falling.lands ~= lands then
		return false, `A {steps}-step drop after the teleport counted a landing at {speed} studs/s`
	end

	-- 3) The same body set down high enough to fall the landing airtime does count its landing
	Teleport.schedule(faller, roblox.CFrame.new(15, floor + HIGH, -15), falling, rig.connection)
	Teleport.run(4)

	lands = falling.lands
	steps, speed = fall(falling)
	if steps > FALL_LIMIT then
		return false, `The body set down high had not stood after {FALL_LIMIT} steps`
	elseif steps <= airtime then
		return false, `The high drop took {steps} steps, too few to pass the {airtime}-tick landing airtime`
	elseif speed <= 0 or falling.lands == lands then
		return false, `A {steps}-step fall after the teleport counted no landing`
	end

	return true, nil
end
