--[[
    A platform's box coming down into a standing body makes that tick's
    depenetration exact, off every tenth command too: one over the body's
    edge pushes it to the first clear spot beside it, and one too wide to
    leave any clear spot leaves it where it stood, stuck
--]]

--!strict
local roblox: any = require("@lune/roblox") -- Its typedefs leave out the datatypes

local Environment = require("../../Environment")

local RIDERS: string = "tests/Fixtures/Step/RiderParity.luau"
local PLATFORMS: string = "src/Step/Platforms.luau"
local SCENE: string = "tests/Fixtures/Step/Scene.luau"
local GEOMETRY: string = "tests/Fixtures/Step/Geometry.luau"
local CONSTANTS: string = "src/Constants.luau"
local MATH: string = "src/Step/Math.luau"

local BOX: number = 8
local START: number = 50
local TICK: number = 51 -- Off every tenth command, so only the press makes the check exact
local DROP: number = 0.25 -- Studs a tick it comes down
local GAP: number = 0.1 -- How far over the head its bottom starts
local X: number = -20 -- On the fixture floor, clear of its other parts
local Z: number = 20
local OVERHANG: number = 2.5 -- How far the narrow box's center sits from the body's along -X

-- A box of the size given, centered off the body's place by offset along X, its bottom gap over a standing head on
-- tick START and coming down by DROP a tick
local function descending(size: any, offset: number, head: number): { [string]: any }
	local center: number = head + GAP + size.Y / 2

	return {
		id = BOX,
		boxes = { { center = roblox.Vector3.zero, size = size } },
		path = function (tick: number, _: number?): any
			return roblox.Vector3.new(X + offset, center - math.max(tick - START, 0) * DROP, Z)
		end,
	}
end

-- A standing body on the floor where the box comes down, the step's give back, and the body, after the tick
local function pressed(platform: { [string]: any }, Riders: any, Platforms: any, feet: vector): (any, number?)
	local world: any = Riders.world()
	Platforms.add(world, platform)
	world.clock = START

	local Scene: any = Environment.load(SCENE)
	local body: any = Scene.state(feet, true)
	local _, stuck: number? = Riders.step(body, Riders.command(), world, TICK)

	return body, stuck
end

return function (): (boolean, string | nil)
	local Riders: any = Environment.load(RIDERS)
	local Platforms: any = Environment.load(PLATFORMS)
	local Scene: any = Environment.load(SCENE)
	local Geometry: any = Environment.load(GEOMETRY)
	local Constants: any = Environment.load(CONSTANTS)
	local Math: any = Environment.load(MATH)

	local settings: any = Scene.settings
	local feet: vector = vector.create(X, Math.quantize(Geometry.floor + Constants.SKIN), Z)
	local head: number = feet.y + settings.standing

	-- 1) A narrow box over the body's -X edge pushes it along +X, at the first distance that clears it
	local narrow: any = roblox.Vector3.new(4, 1, 4)
	local body: any, stuck: number? = pressed(descending(narrow, -OVERHANG, head), Riders, Platforms, feet)
	local reach: number = Constants.DEPENETRATION_FIRST * 2 * settings.radius
	local pushed: number = reach * 2 ^ (Constants.DEPENETRATION_STEPS - 2) -- The first distance past the overhang
	if stuck ~= nil then
		return false, `The narrow box left the body stuck {stuck} deep`
	elseif math.abs(body.position.x - (X + pushed)) > Constants.POSITION_QUANTUM then
		return false, `The narrow box pushed the body to {body.position}, not {pushed} studs along +X`
	end

	local boxEdge: number = X - OVERHANG + narrow.X / 2
	if body.position.x - settings.radius < boxEdge then
		return false, `The body pushed to {body.position.x} still sits under the box's edge at {boxEdge}`
	end

	-- 2) A box wider than every spot depenetration tries leaves the body where it stood, stuck
	local wide: any = roblox.Vector3.new(30, 1, 30)
	local trapped: any, trappedStuck: number? = pressed(descending(wide, 0, head), Riders, Platforms, feet)
	if trappedStuck == nil then
		return false, "A box too wide to leave a clear spot came down into the body and gave back no stuck depth"
	elseif trapped.position.x ~= feet.x or trapped.position.z ~= feet.z then
		return false, `The trapped body moved to {trapped.position} from {feet}`
	end

	return true, nil
end
