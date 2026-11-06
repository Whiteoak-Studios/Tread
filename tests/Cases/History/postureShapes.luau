--[[
    Each posture's hit shapes are placed at the sample's feet and yaw, and
    a lean tilts every point above the posture's waist about it, to the
    right for a positive lean, while points at or below it stay. A swimmer
    is hit through its Crouch shapes and a lying sleeper through Downed's
--]]

--!strict
local Environment = require("../../Environment")

local HISTORY: string = "src/Server/History.luau"
local STATE: string = "src/Step/State.luau"
local EXAMPLE: string = "tests/Fixtures/Config/Example.luau"
local FEET: vector = vector.create(100, 10, 50)
local LEAN: number = 20 -- The example's whole lean limit, so it reads back exactly
local NEAR: number = 1e-5 -- A vector holds float32, so a placed point sits within its rounding of the oracle's

type Point = { name: string, got: vector, want: vector }

-- A point of the example's shapes in own space placed by hand: the lean about the waist, then the yaw and the feet
local function placed(at: Vector3, waist: number, yaw: number, lean: number): vector
	local x: number, y: number, z: number = at.X, at.Y, at.Z

	if y > waist then
		local up: number = y - waist
		local tilt: number = math.rad(lean)
		x, y = x * math.cos(tilt) + up * math.sin(tilt), waist - x * math.sin(tilt) + up * math.cos(tilt)
	end

	return FEET + vector.create(math.cos(yaw) * x + math.sin(yaw) * z, y, -math.sin(yaw) * x + math.cos(yaw) * z)
end

-- Why any point sits apart from where it was due, or nil when each sits there
local function check(points: { Point }): string?
	for _, point: Point in points do
		if vector.magnitude(point.got - point.want) > NEAR then
			return `The {point.name} sat at {point.got}, not {point.want}`
		end
	end

	return nil
end

return function (): (boolean, string | nil)
	local History: any = Environment.load(HISTORY)
	local State: any = Environment.load(STATE)
	local Example: any = Environment.load(EXAMPLE)
	local shared = Example.shared()
	History.start(shared, Example.server())

	local stand = shared.hitShapes.Stand
	local crouch = shared.hitShapes.Crouch
	local downed = shared.hitShapes.Downed
	local state = State.new()
	state.position = FEET

	-- 1) Standing, turned a quarter turn left and leaning right: the right side faces -Z, so the lean tips toward it
	state.facing = math.pi / 2
	state.lean = LEAN
	History.write(0, 1, state, 0)

	local leaning = History.sampleAt(0, 1)
	local headSine: number = (stand.zones.head.from.Y - stand.waist) * math.sin(math.rad(LEAN))

	local failure: string? = check({
		{
			name = "leaning head",
			got = leaning.zones.head.from,
			want = placed(stand.zones.head.from, stand.waist, math.pi / 2, LEAN),
		},
		{
			name = "leaning chest",
			got = leaning.zones.chest.to,
			want = placed(stand.zones.chest.to, stand.waist, math.pi / 2, LEAN),
		},
		{ name = "body's top", got = leaning.body.to, want = placed(stand.body.to, stand.waist, math.pi / 2, LEAN) },
		{
			name = "body's bottom, below the waist",
			got = leaning.body.from,
			want = FEET + vector.create(0, stand.body.from.Y, 0),
		},
		{
			name = "legs, below the waist",
			got = leaning.zones.legs.to,
			want = FEET + vector.create(0, stand.zones.legs.to.Y, 0),
		},
	})

	if failure then
		return false, failure
	elseif
		math.abs(leaning.zones.head.from.z - (FEET.z - headSine)) > NEAR
		or math.abs(leaning.zones.head.from.x - FEET.x) > NEAR
	then
		return false, `Leaning right while facing -X put the head at {leaning.zones.head.from}, not toward -Z`
	elseif leaning.zones.head.radius ~= stand.zones.head.radius or leaning.body.radius ~= stand.body.radius then
		return false, "The placed capsules lost their radii"
	end

	-- 2) Standing, facing -Z and leaning left: the head tips toward -X
	state.facing = 0
	state.lean = -LEAN
	History.write(0, 2, state, 0)

	local left = History.sampleAt(0, 2)
	if math.abs(left.zones.head.from.x - (FEET.x - headSine)) > NEAR then
		return false, `Leaning left while facing -Z put the head at {left.zones.head.from}, not toward -X`
	end

	-- 3) Crouched, upright and facing -Z: its own shapes, moved to the feet
	state.posture = "Crouch"
	state.lean = 0
	History.write(0, 3, state, 0)

	local crouched = History.sampleAt(0, 3)
	failure = check({
		{
			name = "crouched head",
			got = crouched.zones.head.to,
			want = placed(crouch.zones.head.to, crouch.waist, 0, 0),
		},
		{ name = "crouched body", got = crouched.body.from, want = placed(crouch.body.from, crouch.waist, 0, 0) },
	})

	if failure or crouched.posture ~= "Crouch" then
		return false, failure or `A crouched sample read the {crouched.posture} posture`
	end

	-- 4) Downed and facing +Z, its shapes lying along the yaw, none above its waist, so the lean leaves them
	state.posture = "Downed"
	state.facing = math.pi
	state.lean = LEAN
	History.write(0, 4, state, 0)

	local down = History.sampleAt(0, 4)
	failure = check({
		{
			name = "downed head",
			got = down.zones.head.from,
			want = placed(downed.zones.head.from, downed.waist, math.pi, 0),
		},
		{
			name = "downed legs",
			got = down.zones.legs.to,
			want = placed(downed.zones.legs.to, downed.waist, math.pi, 0),
		},
	})

	if failure or down.posture ~= "Downed" then
		return false, failure or `A downed sample read the {down.posture} posture`
	end

	-- 5) Swimming upright: hit through the Crouch shapes, which the sample names
	state.posture = "Stand"
	state.mode = "Swim"
	state.facing = 0
	state.lean = 0
	History.write(0, 5, state, 0)

	local swimmer = History.sampleAt(0, 5)
	failure = check({
		{
			name = "swimmer's head",
			got = swimmer.zones.head.from,
			want = placed(crouch.zones.head.from, crouch.waist, 0, 0),
		},
	})

	if failure or swimmer.posture ~= "Crouch" then
		return false, failure or `A swimmer's sample named the {swimmer.posture} posture, not Crouch`
	end

	-- 6) A lying sleeper's sample, seeded at wake: the Downed shapes whatever its word says
	History.seed(1, 5, { epoch = 0, position = FEET, platform = 0, yaw = 0 })

	local lying = History.sampleAt(1, 5)
	failure = check({
		{ name = "lying head", got = lying.zones.head.from, want = placed(downed.zones.head.from, downed.waist, 0, 0) },
	})

	if failure or lying.posture ~= "Downed" then
		return false, failure or `A lying sample named the {lying.posture} posture, not Downed`
	end

	return true, nil
end
