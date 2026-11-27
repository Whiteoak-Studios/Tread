--[[
    A sample's aim pitch, as its i16 holds it, tilts the hit shapes above
    the waist, between two samples at the lerp of theirs, clamped to a
    quarter turn, while lying, seeded and downed shapes stay where they lie
--]]

--!strict
local Environment = require("../../Environment")

local HISTORY: string = "src/Server/History.luau"
local STATE: string = "src/Step/State.luau"
local CONSTANTS: string = "src/Constants.luau"
local EXAMPLE: string = "tests/Fixtures/Config/Example.luau"
local FEET: vector = vector.create(100, 10, 50)
local YAW: number = math.pi / 2 -- Facing -X, so the pitch tips the head back along +X
local LEAN: number = 20 -- The example's whole lean limit, so it reads back exactly
local UP: number = 0.5 -- Radians of aim pitch at the first tick
local DOWN: number = -0.3 -- And at the next
local PAST: number = 2 -- Radians, past the quarter turn a sample's pitch holds
local QUARTER_TURN: number = math.pi / 2 -- Radians, the most a sample's pitch holds either way
local DOWNED_PITCH: number = 0.8
local LEVEL: number = 0 -- Radians of aim pitch, none
local AHEAD: number = 0 -- A yaw that faces -Z, as a lying body is placed along
local UNLEANED: number = 0 -- Degrees of lean, none
local EPOCH: number = 0
local HALF: number = 0.5 -- The fraction halfway between two ticks
local NEAR: number = 1e-5 -- A vector holds float32, so a placed point sits within its rounding of the oracle's
local LERPED: number = 1e-4

local AIMED: number = 0 -- The slot written with the pitches
local CONTROL: number = 1 -- The same states written level
local SEEDED: number = 2
local LYING: number = 3

type Point = { name: string, got: vector, want: vector }

-- A point of the example's shapes in own space placed by hand: the lean, then the pitch about the waist, the yaw last
local function placed(at: Vector3, waist: number, yaw: number, lean: number, pitch: number): vector
	local x: number, y: number, z: number = at.X, at.Y, at.Z

	if y > waist then
		local up: number = y - waist
		local tilt: number = math.rad(lean)
		local leanX: number = x * math.cos(tilt) + up * math.sin(tilt)
		local leanY: number = -x * math.sin(tilt) + up * math.cos(tilt)
		x, y, z =
			leanX, waist + leanY * math.cos(pitch) - z * math.sin(pitch), leanY * math.sin(pitch) + z * math.cos(pitch)
	end

	return FEET + vector.create(math.cos(yaw) * x + math.sin(yaw) * z, y, -math.sin(yaw) * x + math.cos(yaw) * z)
end

-- Why any point sits further than near from where it was due, or nil when each sits there
local function check(points: { Point }, near: number): string?
	for _, point: Point in points do
		if vector.magnitude(point.got - point.want) > near then
			return `The {point.name} sat at {point.got}, not {point.want}`
		end
	end

	return nil
end

-- Why any point of one sample's shapes differs at all from another's, or nil when every one is the same
local function same(got: any, want: any, what: string): string?
	if got.body.from ~= want.body.from or got.body.to ~= want.body.to then
		return `{what}: the body sat from {got.body.from} to {got.body.to}, not {want.body.from} to {want.body.to}`
	end

	for name: string, shape: any in want.zones do
		local other: any = got.zones[name]
		if other.from ~= shape.from or other.to ~= shape.to then
			return `{what}: the {name} sat from {other.from} to {other.to}, not {shape.from} to {shape.to}`
		end
	end

	return nil
end

return function (): (boolean, string | nil)
	local History: any = Environment.load(HISTORY)
	local State: any = Environment.load(STATE)
	local Constants: any = Environment.load(CONSTANTS)
	local Example: any = Environment.load(EXAMPLE)
	local shared = Example.shared()
	History.start(shared, Example.server())

	local stand = shared.hitShapes.Stand
	local downed = shared.hitShapes.Downed
	local scale: number = Constants.PITCH_LIMIT / QUARTER_TURN -- A sample's i16 steps a radian of pitch

	-- A pitch as a sample holds it, in whole steps and held to a quarter turn either way
	local function quantized(pitch: number): number
		return math.clamp(math.round(pitch * scale), -Constants.PITCH_LIMIT, Constants.PITCH_LIMIT) / scale
	end

	local state = State.new()
	state.position = FEET
	state.facing = YAW
	state.lean = LEAN

	History.write(AIMED, 1, state, UP)
	History.write(CONTROL, 1, state, LEVEL)
	History.write(AIMED, 2, state, DOWN)
	History.write(CONTROL, 2, state, LEVEL)

	-- 1) On the first tick, the head and chest sit at its quantized pitch, the head tipped back along +X
	local first = History.sampleAt(AIMED, 1)
	local up: number = quantized(UP)
	local failure: string? = check({
		{
			name = "head's bottom",
			got = first.zones.head.from,
			want = placed(stand.zones.head.from, stand.waist, YAW, LEAN, up),
		},
		{
			name = "head's top",
			got = first.zones.head.to,
			want = placed(stand.zones.head.to, stand.waist, YAW, LEAN, up),
		},
		{
			name = "chest's top",
			got = first.zones.chest.to,
			want = placed(stand.zones.chest.to, stand.waist, YAW, LEAN, up),
		},
		{ name = "body's top", got = first.body.to, want = placed(stand.body.to, stand.waist, YAW, LEAN, up) },
	}, NEAR)

	if failure then
		return false, `On the first tick: {failure}`
	end

	local headX: number = first.zones.head.from.x
	local level = History.sampleAt(CONTROL, 1)
	if not (headX > level.zones.head.from.x) then
		return false,
			`Aiming up while facing -X put the head at x {headX}, not back of the level head's {level.zones.head.from.x}`
	end

	-- Below the waist, the pitched sample's points are the level one's, bit for bit
	local legsFrom: vector, legsTo: vector, bodyFrom: vector =
		first.zones.legs.from, first.zones.legs.to, first.body.from
	if legsFrom ~= level.zones.legs.from or legsTo ~= level.zones.legs.to or bodyFrom ~= level.body.from then
		return false, `The pitch moved the legs to {legsFrom} and {legsTo} or the body's bottom to {bodyFrom}`
	end

	-- 2) Halfway to the next tick, the pitch is the lerp of the two quantized pitches
	local halfway = History.sampleAt(AIMED, 1 + HALF)
	local between: number = up + (quantized(DOWN) - up) * HALF
	failure = check({
		{
			name = "head's bottom",
			got = halfway.zones.head.from,
			want = placed(stand.zones.head.from, stand.waist, YAW, LEAN, between),
		},
		{ name = "body's top", got = halfway.body.to, want = placed(stand.body.to, stand.waist, YAW, LEAN, between) },
	}, LERPED)

	if failure then
		return false, `Halfway: {failure}`
	end

	local halfLegs: vector, halfBody: vector = halfway.zones.legs.from, halfway.body.from
	local levelHalf = History.sampleAt(CONTROL, 1 + HALF)
	if halfLegs ~= levelHalf.zones.legs.from or halfBody ~= levelHalf.body.from then
		return false, `Halfway, the pitch moved the legs' bottom to {halfLegs} or the body's bottom to {halfBody}`
	end

	-- 3) A pitch past a quarter turn either way reads back at the quarter turn
	History.write(AIMED, 3, state, PAST)
	History.write(AIMED, 4, state, -PAST)

	local high = History.sampleAt(AIMED, 3)
	failure = check({
		{
			name = "head's top",
			got = high.zones.head.to,
			want = placed(stand.zones.head.to, stand.waist, YAW, LEAN, QUARTER_TURN),
		},
	}, NEAR)

	if failure then
		return false, `Aimed past straight up: {failure}`
	end

	local low = History.sampleAt(AIMED, 4)
	failure = check({
		{
			name = "head's top",
			got = low.zones.head.to,
			want = placed(stand.zones.head.to, stand.waist, YAW, LEAN, -QUARTER_TURN),
		},
	}, NEAR)

	if failure then
		return false, `Aimed past straight down: {failure}`
	end

	-- 4) A downed body aiming up keeps its shapes where a level one's lie, none of them above its waist
	state.posture = "Downed"
	History.write(AIMED, 5, state, DOWNED_PITCH)
	History.write(CONTROL, 5, state, LEVEL)

	local downedAimed = History.sampleAt(AIMED, 5)
	failure = same(downedAimed, History.sampleAt(CONTROL, 5), "Downed and aiming up")
	if failure then
		return false, failure
	end

	-- 5) A seeded sleeper and one placed lying sit where the Downed shapes lie level
	History.seed(SEEDED, 5, { epoch = EPOCH, position = FEET, platform = 0, yaw = AHEAD })

	local seeded = History.sampleAt(SEEDED, 5)
	local lying = History.lying(LYING, FEET, AHEAD, EPOCH)
	failure = check({
		{
			name = "seeded head",
			got = seeded.zones.head.from,
			want = placed(downed.zones.head.from, downed.waist, AHEAD, UNLEANED, LEVEL),
		},
		{
			name = "seeded legs",
			got = seeded.zones.legs.to,
			want = placed(downed.zones.legs.to, downed.waist, AHEAD, UNLEANED, LEVEL),
		},
	}, NEAR) or same(lying, seeded, "Lying")

	if failure then
		return false, failure
	end

	return true, nil
end
