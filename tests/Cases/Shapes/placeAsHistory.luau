--[[
    Shapes.place puts the example's crossed shapes, for fixed feet, yaws and
    leans, at exactly the points the history's own placement gave before it
    moved into Shapes, the values below as History.sampleAt read them back
--]]

--!strict
local Environment = require("../../Environment")

local SHAPES: string = "src/Step/Shapes.luau"
local EXAMPLE: string = "tests/Fixtures/Config/Example.luau"
local YAW_SCALE: number = 65536 / (2 * math.pi) -- A sample's u16 yaw steps a radian, as the history reads its yaw back
local LEAN_STEPS: number = 127 -- A sample's i8 lean steps to the lean limit, as the history reads its lean back
local LEVEL: number = 0 -- The aim pitch, radians, which leaves the lean's placement as it was

type Capsule = { from: vector, to: vector, radius: number }

-- One placement: the posture's shapes, the feet, the yaw in u16 steps and the lean in i8 steps, and what it gave
type Placement = {
	name: string,
	posture: string,
	feet: vector,
	yawSteps: number,
	leanSteps: number,
	body: Capsule,
	zones: { [string]: Capsule },
}

local PLACEMENTS: { Placement } = {
	{
		name = "standing, leaning right",
		posture = "Stand",
		feet = vector.create(100.5, 10.25, -50.75),
		yawSteps = 12000,
		leanSteps = 127,
		body = {
			from = vector.create(100.5, 11.25, -50.75),
			to = vector.create(100.70933532714844, 14.159539222717285, -51.218376159667969),
			radius = 1.4,
		},
		zones = {
			chest = {
				from = vector.create(100.55582427978516, 13.125877380371094, -50.874900817871094),
				to = vector.create(100.69538116455078, 14.065569877624512, -51.187152862548828),
				radius = 0.9,
			},
			head = {
				from = vector.create(100.75120544433594, 14.441447257995605, -51.312053680419922),
				to = vector.create(100.80702972412109, 14.817323684692383, -51.436954498291016),
				radius = 0.5,
			},
			legs = {
				from = vector.create(100.5, 10.649999618530273, -50.75),
				to = vector.create(100.5, 12.25, -50.75),
				radius = 0.7,
			},
		},
	},
	{
		name = "crouched, leaning left",
		posture = "Crouch",
		feet = vector.create(-2000.25, -3.5, 812.125),
		yawSteps = 40000,
		leanSteps = -64,
		body = {
			from = vector.create(-2000.25, -2.5999999046325684, 812.125),
			to = vector.create(-2000.142333984375, -1.2123454809188843, 812.0355224609375),
			radius = 1.3,
		},
		zones = {
			chest = {
				from = vector.create(-2000.2230224609375, -1.8030862808227539, 812.10260009765625),
				to = vector.create(-2000.12890625, -1.1138885021209717, 812.02435302734375),
				radius = 0.9,
			},
			head = {
				from = vector.create(-2000.1019287109375, -0.91697508096694946, 812.001953125),
				to = vector.create(-2000.0615234375, -0.62160444259643555, 811.9683837890625),
				radius = 0.5,
			},
			legs = {
				from = vector.create(-2000.25, -3.0999999046325684, 812.125),
				to = vector.create(-2000.25, -2, 812.125),
				radius = 0.7,
			},
		},
	},
	{
		name = "downed, turned and leaning right",
		posture = "Downed",
		feet = vector.create(100.5, 10.25, -50.75),
		yawSteps = 50000,
		leanSteps = 127,
		body = {
			from = vector.create(98.905288696289062, 10.850000381469727, -50.620059967041016),
			to = vector.create(102.09471130371094, 10.850000381469727, -50.879940032958984),
			radius = 0.8,
		},
		zones = {
			chest = {
				from = vector.create(101.09801483154297, 10.850000381469727, -50.798725128173828),
				to = vector.create(102.09471130371094, 10.850000381469727, -50.879940032958984),
				radius = 0.8,
			},
			head = {
				from = vector.create(102.69273376464844, 10.850000381469727, -50.928665161132812),
				to = vector.create(102.99174499511719, 10.850000381469727, -50.953029632568359),
				radius = 0.5,
			},
			legs = {
				from = vector.create(100.101318359375, 10.850000381469727, -50.717514038085938),
				to = vector.create(98.307266235351562, 10.850000381469727, -50.571334838867188),
				radius = 0.6,
			},
		},
	},
	{
		name = "a swimmer's crouched shapes, upright",
		posture = "Crouch",
		feet = vector.create(7.015625, 0.03125, -7.984375),
		yawSteps = 30000,
		leanSteps = 0,
		body = {
			from = vector.create(7.015625, 0.93124997615814209, -7.984375),
			to = vector.create(7.015625, 2.3312499523162842, -7.984375),
			radius = 1.3,
		},
		zones = {
			chest = {
				from = vector.create(7.015625, 1.7312500476837158, -7.984375),
				to = vector.create(7.015625, 2.4312500953674316, -7.984375),
				radius = 0.9,
			},
			head = {
				from = vector.create(7.015625, 2.6312499046325684, -7.984375),
				to = vector.create(7.015625, 2.9312500953674316, -7.984375),
				radius = 0.5,
			},
			legs = {
				from = vector.create(7.015625, 0.43125000596046448, -7.984375),
				to = vector.create(7.015625, 1.53125, -7.984375),
				radius = 0.7,
			},
		},
	},
}

-- Why a placed capsule sits off the one the history gave, or nil when it sits exactly there
local function off(name: string, got: Capsule?, want: Capsule): string?
	if got == nil then
		return `The {name} capsule wasn't placed`
	elseif got.from ~= want.from or got.to ~= want.to or got.radius ~= want.radius then
		return `The {name} capsule sat from {got.from} to {got.to} at {got.radius}, not {want.from} to {want.to}`
	end

	return nil
end

return function (): (boolean, string | nil)
	local Shapes: any = Environment.load(SHAPES)
	local Example: any = Environment.load(EXAMPLE)
	local shared = Example.shared()
	local limit: number = shared.step.lean

	for _, placement: Placement in PLACEMENTS do
		local from = Shapes.cross(shared.hitShapes[placement.posture])
		local into = Shapes.cross(shared.hitShapes[placement.posture])
		local yaw: number = placement.yawSteps / YAW_SCALE
		local lean: number = placement.leanSteps * limit / LEAN_STEPS

		Shapes.place(from, into, placement.feet, yaw, lean, LEVEL)

		local failure: string? = off("body", into.body, placement.body)
		for name: string, want: Capsule in placement.zones do
			failure = failure or off(name, into.zones[name], want)
		end

		if failure then
			return false, `{placement.name}: {failure}`
		end
	end

	return true, nil
end
