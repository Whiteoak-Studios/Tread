--[[
    Predict.mantle gives where a jump press at the newest predicted tick
    would end a mantle: nil before start and the first OwnerState, the
    riser's top facing it, one search a predicted tick, nil facing away or
    downed, and nil when the search throws, never throwing itself
--]]

--!strict
local Environment = require("../../Environment")
local Harness = require("../../Fixtures/Predict/Harness")

local PREDICT: string = "src/Client/Predict.luau"
local MANTLE: string = "src/Step/Mantle.luau"
local SCENE: string = "tests/Fixtures/Step/Scene.luau"
local GEOMETRY: string = "tests/Fixtures/Step/Geometry.luau"

local EAST: number = -math.pi / 2 -- A yaw that looks along +X, at the riser's west face
local WEST: number = math.pi / 2
local RISE: number = 1.03125 -- From feet resting on the floor to a skin over the 1-stud riser, on the rise's 1/32 steps
local DEPTH: number = 1 -- The spawn OwnerState's queue, inside the band

return function (): (boolean, string | nil)
	local unstarted: any = Environment.load(PREDICT)
	local ranUnstarted: boolean, early: any = pcall(unstarted.mantle)
	if not ranUnstarted or early ~= nil then
		return false, `Predict.mantle before start gave {early}, where nil was expected`
	end

	local Mantle: any = Environment.load(MANTLE)
	local Scene: any = Environment.load(SCENE)
	local Geometry: any = Environment.load(GEOMETRY)

	local rig: any = Harness.new()
	local Predict: any = rig.Predict
	local Math: any = rig.Math
	local settings: any = Scene.settings
	local skin: number = rig.Constants.SKIN

	if Predict.mantle() ~= nil then
		return false, "Predict.mantle before the first OwnerState gave a point"
	end

	-- A body standing a skin from the riser's west face, looking at it
	local riser: any = Geometry.riser
	local face: number = riser.center.x - riser.size.x / 2
	local resting: number = Math.quantize(Geometry.floor + skin)
	local function facingRiser(): any
		local state: any =
			Scene.state(vector.create(Math.quantize(face - settings.radius - skin), resting, riser.center.z), true)
		state.facing = EAST
		state.groundHeight = resting
		state.tick = 100
		state.fields = { beingRevived = false }
		state.block = { sinceJump = 0, sinceShot = 15 }

		return state
	end

	local start: any = facingRiser()
	Predict.receive(rig.owner(start, DEPTH))

	-- Each search's casts, counted where prediction's world makes them
	local collision: any = rig.world.collision
	local sweep: any = collision.sweep
	local casts: number = 0
	collision.sweep = function (...: any): any
		casts += 1

		return sweep(...)
	end

	local point: vector? = Predict.mantle()
	local over: number = Math.quantize(2 * settings.radius + 2 * skin)
	local expected: vector = vector.create(start.position.x + over, resting + RISE, riser.center.z)
	if point == nil then
		return false, "Predict.mantle facing the riser gave no point"
	elseif point ~= expected then
		return false, `Predict.mantle facing the riser gave {point}, where the path ends at {expected}`
	elseif point ~= Mantle.ending(Predict.state(), rig.world) then
		return false, `Predict.mantle gave {point}, where the step's own search ends at another point`
	end

	local searched: number = casts
	if searched == 0 then
		return false, "Predict.mantle's first call made no cast"
	end

	local again: vector? = Predict.mantle()
	if again ~= point or casts ~= searched then
		return false, `A second call on the same tick gave {again} after {casts - searched} more casts`
	end

	-- A tick that turns the body away searches again, and finds nothing
	rig.input = function (command: any, _: number)
		command.yaw = WEST
		command.fields.slot = 0
		command.fields.shots = {}
	end

	rig.frames(1)
	local afterTick: number = casts
	local away: vector? = Predict.mantle()
	if away ~= nil then
		return false, `Predict.mantle facing away from the riser gave {away}`
	elseif casts == afterTick then
		return false, "Predict.mantle after a new predicted tick made no cast, so it searched nothing"
	end

	-- A downed body mantles nothing
	local downedRig: any = Harness.new()
	local downed: any = facingRiser()
	downed.posture = "Downed"
	downedRig.Predict.receive(downedRig.owner(downed, DEPTH))
	if downedRig.Predict.mantle() ~= nil then
		return false, "Predict.mantle for a downed body gave a point"
	end

	-- A search that throws answers nil, and the call itself never throws
	local brokenRig: any = Harness.new()
	brokenRig.Predict.receive(brokenRig.owner(facingRiser(), DEPTH))
	brokenRig.world.collision.sweep = function (): any
		error("The game's sweep threw")
	end

	local ranBroken: boolean, broken: any = pcall(brokenRig.Predict.mantle)
	if not ranBroken or broken ~= nil then
		return false, `Predict.mantle over a throwing sweep gave {broken}, where nil was expected`
	end

	return true, nil
end
