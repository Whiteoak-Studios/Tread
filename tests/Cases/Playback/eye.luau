--[[
    While a playback runs, getEye gives the target's cleared eye drawn
    between its two OwnerStates around the clip tick, looking along the
    newest command it stepped by the drawn tick, never a blend of two
    looks; before the first render and after the end it gives the live eye
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
local SECOND_AT: vector = vector.create(2, 0, 0)
local EYE_HEIGHT: number = 4.15625 -- Studs, on OwnerState's 1/32 grid
local FIRST_YAW: number = 0.5 -- Radians, the command stepped on the first OwnerState's tick
local SECOND_YAW: number = -0.4
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

	-- An OwnerState of the target standing at a place, its eye eased to the height it stands at
	local function owner(at: vector, tick: number, yaw: number): { [string]: any }
		local state: any = clip.state(at, tick)
		state.eyeHeight = EYE_HEIGHT

		return {
			slot = TARGET,
			generation = GENERATION,
			state = state,
			lag = 0,
			looks = { { yaw = yaw, pitch = 0, headYaw = 0, headPitch = 0 } },
		}
	end

	local ticks: { buffer } = {
		clip.keyframe({ tick = K }),
		clip.frame({ tick = K, owner = owner(FIRST_AT, K, FIRST_YAW) }),
		clip.frame({ tick = K + 1, owner = owner(SECOND_AT, K + 1, SECOND_YAW) }),
		clip.frame({ tick = K + 2, owner = owner(SECOND_AT, K + 2, SECOND_YAW) }),
	}

	-- Whether getEye gives an eye and look, and why not
	local function sees(at: vector, look: vector, when: string): string?
		local eye: Vector3, direction: Vector3 = handle:getEye()

		if math.abs(eye.X - at.x) > CLOSE or math.abs(eye.Y - at.y) > CLOSE or math.abs(eye.Z - at.z) > CLOSE then
			return `{when}, the eye was at {eye}, not {at}`
		elseif
			math.abs(direction.X - look.x) > CLOSE
			or math.abs(direction.Y - look.y) > CLOSE
			or math.abs(direction.Z - look.z) > CLOSE
		then
			return `{when}, the eye looked along {direction}, not {look}`
		end

		return nil
	end

	local ahead: vector = Public.look(0, 0, 0, 0, cone)
	local live: vector = OWN_AT
	local playback: any = handle:play(ticks)

	-- 1) Before the first render the eye stays where it was last drawn, the owner's
	local problem: string? = sees(live, ahead, "Before the first render")
	if problem then
		return false, problem
	end

	-- 2) Half a tick on, between the two OwnerStates, along the command stepped on the drawn tick, not a blend
	playback:render(0.5 / relay)
	local halfway: vector = (FIRST_AT + SECOND_AT) / 2 + vector.create(0, EYE_HEIGHT, 0)
	problem = sees(halfway, Public.look(FIRST_YAW, 0, 0, 0, cone), "Half a tick on")
	if problem then
		return false, problem
	end

	-- 3) A tick on, at the second OwnerState and its own command's look
	playback:render(1 / relay)
	problem = sees(SECOND_AT + vector.create(0, EYE_HEIGHT, 0), Public.look(SECOND_YAW, 0, 0, 0, cone), "A tick on")
	if problem then
		return false, problem
	end

	-- 4) The end gives the live eye back
	playback:destroy()
	problem = sees(live, ahead, "After the playback's end")
	if problem then
		return false, problem
	end

	return true, nil
end
