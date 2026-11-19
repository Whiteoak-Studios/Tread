--[[
    A sleeper and a body are drawn lying whatever their records hold: on
    the ground in the Downed posture at rest, with no sprint, aim, lean or
    aim pitch, at the record's place and yaw, while a player with the same
    records stands
--]]

--!strict
local Viewer = require("../../Fixtures/Interpolate/Viewer")

local SLEEPER: number = 40
local BODY: number = 41
local PLAYER: number = 42
local GENERATION: number = 1
local TICK: number = 10
local REPEATS: number = 3 -- Blocks after the first, each repeating the reveal until it is acknowledged
local AT: vector = vector.create(5, 2, -3)
local YAW: number = 1.25 -- Radians
local PITCH: number = 0.5
local LEAN: number = 10 -- Degrees
local CLOSE: number = 1e-3 -- Radians a quantized yaw may sit off the one written
local PITCH_STEP: number = 0.013 -- Radians a record's i8 pitch steps by, about 90° over 127
local LEAN_STEP: number = 0.16 -- Degrees a record's lean steps by, 20° over 127

return function (): (boolean, string | nil)
	local viewer = Viewer.new()
	local Interpolate: any = viewer.Interpolate

	-- Records that say standing, sprinting and aiming in the air, pitched up and leaning
	local word: number = viewer.word({ mode = "Air", posture = "Stand", sprint = true, aim = true })
	local kinds: { [number]: string } = { [SLEEPER] = "Sleeper", [BODY] = "Body", [PLAYER] = "Player" }

	for slot: number in kinds do
		viewer.announce(slot, GENERATION, "A")
	end

	for tick: number = TICK, TICK + REPEATS do
		local reveals: { any } = {}
		local records: { any } = {}

		for slot: number, kind: string in kinds do
			table.insert(reveals, { slot = slot, generation = GENERATION, kind = kind })
			table.insert(records, {
				slot = slot,
				generation = GENERATION,
				position = AT,
				yaw = YAW,
				pitch = PITCH,
				lean = LEAN,
				word = word,
			})
		end

		viewer.send({ tick = tick, reveals = reveals, records = records })
	end

	Interpolate.frame(0)

	for _, slot: number in { SLEEPER, BODY } do
		local drawn: boolean, state: any, pitch: number = viewer.pose(slot)

		if not drawn then
			return false, `The {kinds[slot]} drew nothing`
		elseif state.mode ~= "Ground" or state.posture ~= "Downed" or not state.grounded then
			return false, `The {kinds[slot]} was drawn {state.mode} and {state.posture}, not lying on the ground`
		elseif state.velocity ~= vector.zero or state.sprint or state.aim or state.lean ~= 0 then
			return false, `The {kinds[slot]} was drawn moving, sprinting, aiming or leaning, not at rest`
		elseif pitch ~= 0 then
			return false, `The {kinds[slot]} was drawn with an aim pitch of {pitch}`
		elseif state.position ~= AT or math.abs(state.facing - YAW) > CLOSE then
			return false, `The {kinds[slot]} lay at {state.position} facing {state.facing}, not {AT} facing {YAW}`
		end
	end

	-- The same records on a player stand as they say
	local drawn: boolean, state: any, pitch: number = viewer.pose(PLAYER)
	if not drawn or state.posture ~= "Stand" or state.mode ~= "Air" or not state.sprint then
		return false, "A player with the same records was drawn lying"
	elseif math.abs(state.lean - LEAN) > LEAN_STEP or math.abs(pitch - PITCH) > PITCH_STEP then
		return false, `The player leaned {state.lean} with an aim pitch of {pitch}, not {LEAN} and {PITCH}`
	end

	return true, nil
end
