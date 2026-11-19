--[[
    A death in a clip shows as the dying player's hide and the body's own
    reveal, the body drawn lying at its record, and a sleeper moved down
    falls from where it lay, halfway through its fall's time at a quarter
    of its drop
--]]

--!strict
local Clip = require("../../Fixtures/Playback/Clip")
local Handle = require("../../Fixtures/Client/Handle")

local K: number = 1000
local FRAMES: number = 20
local DYING: number = 30
local BODY: number = 31
local SLEEPER: number = 32
local TARGET: number = 9
local GENERATION: number = 1
local DEATH: number = 4 -- Ticks after the keyframe the hide and the body's reveal come
local MOVE: number = 6 -- Ticks after the keyframe the sleeper's move comes
local LYING_AT: vector = vector.create(10, 0, 0)
local SLEPT_AT: vector = vector.create(0, 20, 0)
local DROPPED_AT: vector = vector.zero
local CLOSE: number = 1e-6

return function (): (boolean, string | nil)
	local rig: any = Handle.new()
	local handle: any = rig.handle
	rig.handshake()

	local clip: any = Clip.new(rig)
	local log: any = Clip.log(rig)
	local relay: number = rig.shared.rates.relay
	local gravity: number = rig.shared.step.gravity
	local Math: any = rig.globals.require(rig.tread.Step.Math)

	local ticks: { buffer } = {
		clip.keyframe({
			tick = K,
			characters = {
				{ slot = DYING, generation = GENERATION, kind = "Player", record = { position = LYING_AT } },
				{ slot = SLEEPER, generation = GENERATION, kind = "Sleeper", record = { position = SLEPT_AT } },
			},
		}),
	}

	for index: number = 0, FRAMES - 1 do
		local tick: number = K + index
		local spec: { [string]: any } = { tick = tick, records = {} }

		if index == DEATH then
			spec.hides = { { slot = DYING, generation = GENERATION } }
			spec.reveals = { { slot = BODY, generation = GENERATION, kind = "Body" } }
			spec.records = { { slot = BODY, generation = GENERATION, position = LYING_AT } }
		elseif index == MOVE then
			spec.reveals = { { slot = SLEEPER, generation = GENERATION, kind = "Sleeper" } }
			spec.records = { { slot = SLEEPER, generation = GENERATION, position = DROPPED_AT } }
		end

		table.insert(
			ticks,
			clip.frame({
				tick = tick,
				blocks = { spec },
				owner = { slot = TARGET, generation = GENERATION, state = clip.state(vector.zero, tick), lag = 0 },
			})
		)
	end

	local playback: any = handle:play(ticks)

	-- 1) Past the death the dying player is gone and the body is drawn lying at its record
	local count: number = #log.poses
	local drop: number = SLEPT_AT.y - DROPPED_AT.y
	local half: number = math.sqrt(2 * drop / gravity) / 2
	playback:render(MOVE / relay + half)

	local drawn: { [number]: any } = log.since(count)
	local body: any = drawn[BODY]
	if Clip.out(rig.pool)[DYING] ~= nil then
		return false, "The dying player's rig stayed out past its hide"
	elseif body == nil then
		return false, "The body its reveal brought wasn't drawn"
	elseif body.posture ~= "Downed" or body.mode ~= "Ground" or body.velocity ~= vector.zero then
		return false, `The body was drawn {body.posture} in {body.mode}, not lying`
	elseif vector.magnitude(body.position - LYING_AT) > CLOSE then
		return false, `The body was drawn at {body.position}, not its record's {LYING_AT}`
	end

	-- 2) The sleeper, halfway through its fall's time, sits where the fall puts it then
	local sleeper: any = drawn[SLEEPER]
	local expected: vector = Math.fall(SLEPT_AT, DROPPED_AT, gravity, half)
	if sleeper == nil then
		return false, "The sleeper wasn't drawn"
	elseif sleeper.posture ~= "Downed" then
		return false, `The sleeper was drawn {sleeper.posture}, not lying`
	elseif vector.magnitude(sleeper.position - expected) > CLOSE then
		return false, `The sleeper was drawn at {sleeper.position}, not its fall's {expected} halfway through it`
	end

	playback:destroy()

	return true, nil
end
