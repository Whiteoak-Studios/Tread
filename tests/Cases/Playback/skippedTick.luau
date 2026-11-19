--[[
    A clip whose frames skip a relay tick, as a catch-up's do, draws the
    target across the gap: its rig stays out, its eye blends between the
    OwnerStates either side, and its look is the skipped tick's command's
--]]

--!strict
local Clip = require("../../Fixtures/Playback/Clip")
local Handle = require("../../Fixtures/Client/Handle")

local K: number = 400
local OWN: number = 2
local TARGET: number = 9
local GENERATION: number = 1
local OWN_AT: vector = vector.create(0, 50, 0) -- The live owner's feet, far from the target's
local FIRST_AT: vector = vector.zero
local SECOND_AT: vector = vector.create(4, 0, 0)
local EYE_HEIGHT: number = 4.15625 -- Studs, on OwnerState's 1/32 grid
local FIRST_YAW: number = 0.5 -- Radians, the command stepped on the first frame's tick
local SKIPPED_YAW: number = -0.4 -- The command stepped on the skipped tick, which the next frame carries
local LAST_YAW: number = 0.2 -- And the one stepped on that frame's own tick
local GAP: number = 2 -- Relay ticks between the two frames
local CLOSE: number = 1e-4

return function (): (boolean, string | nil)
	local rig: any = Handle.new()
	local handle: any = rig.handle
	local Public: any = rig.globals.require(rig.tread.Step.Public)
	local cone: number = rig.shared.step.headCone
	local relay: number = rig.shared.rates.relay

	rig.handshake()
	rig.own(OWN, GENERATION)
	rig.owner(rig.body(OWN_AT, 0, K))
	rig.frames(1)

	local clip: any = Clip.new(rig)
	Clip.log(rig)

	-- An OwnerState of the target standing at a place, with the yaws it stepped since the frame before, newest first
	local function owner(at: vector, tick: number, yaws: { number }): { [string]: any }
		local state: any = clip.state(at, tick)
		state.eyeHeight = EYE_HEIGHT

		local looks: { any } = {}
		for _, yaw: number in yaws do
			table.insert(looks, { yaw = yaw, pitch = 0, headYaw = 0, headPitch = 0 })
		end

		return { slot = TARGET, generation = GENERATION, state = state, lag = 0, looks = looks }
	end

	local playback: any = handle:play({
		clip.keyframe({ tick = K }),
		clip.frame({ tick = K, owner = owner(FIRST_AT, K, { FIRST_YAW }) }),
		clip.frame({ tick = K + GAP, owner = owner(SECOND_AT, K + GAP, { LAST_YAW, SKIPPED_YAW }) }),
	})

	-- At the skipped tick, halfway across the gap
	playback:render(1 / relay)

	local eye: Vector3, direction: Vector3 = handle:getEye()
	local at: vector = (FIRST_AT + SECOND_AT) / 2 + vector.create(0, EYE_HEIGHT, 0)
	local look: vector = Public.look(SKIPPED_YAW, 0, 0, 0, cone)

	if Clip.out(rig.pool)[TARGET] == nil then
		return false, "At the skipped tick the target's rig was put away"
	elseif math.abs(eye.X - at.x) > CLOSE or math.abs(eye.Y - at.y) > CLOSE or math.abs(eye.Z - at.z) > CLOSE then
		return false, `At the skipped tick the eye was at {eye}, not halfway across the gap at {at}`
	elseif
		math.abs(direction.X - look.x) > CLOSE
		or math.abs(direction.Y - look.y) > CLOSE
		or math.abs(direction.Z - look.z) > CLOSE
	then
		return false, `At the skipped tick the eye looked along {direction}, not the skipped tick's command's {look}`
	end

	playback:destroy()

	return true, nil
end
