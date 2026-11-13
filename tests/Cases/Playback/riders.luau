--[[
    A clip draws a rider on its platform's copy, placed where the platform's
    path puts it at the target's drawn tick from the keyframe's press, the
    tick unwrapped at or after that press, not on the live clock
--]]

--!strict
local roblox: any = require("@lune/roblox") -- Its typedefs leave out the datatypes

local Clip = require("../../Fixtures/Playback/Clip")
local Handle = require("../../Fixtures/Client/Handle")

local PLATFORM: number = 1
local PRESS: number = 70000 -- The press's simulation tick, past one wrap of a u16
local SINCE: number = 10 -- Simulation ticks from the press to the keyframe
local RISE: number = 0.25 -- Studs the platform rises a tick after its press
local TOP: number = 40 -- Ticks after its press it rises for
local FLOOR: any = roblox.Vector3.new(4, 1, 4) -- Its one box's size
local FRAMES: number = 20
local RIDER: number = 40
local TARGET: number = 9
local GENERATION: number = 1
local WIRE: number = 2 ^ 16
local ABOARD: vector = vector.create(1, 0.5, 0) -- The rider's place in the platform's own space
local AHEAD: number = 10 -- Ticks after the keyframe it is drawn at
local CLOSE: number = 1e-6

return function (): (boolean, string | nil)
	local rig: any = Handle.new()
	local handle: any = rig.handle
	rig.handshake()

	local function path(tick: number, calledAt: number?): any
		if calledAt == nil then
			return roblox.Vector3.new(0, 0, 0)
		end

		return roblox.Vector3.new(0, math.min(tick - calledAt, TOP) * RISE, 0)
	end

	handle:addPlatform({
		id = PLATFORM,
		boxes = { { center = roblox.Vector3.new(0, 0, 0), size = FLOOR } },
		path = path,
	})

	local clip: any = Clip.new(rig)
	local log: any = Clip.log(rig)
	local relay: number = rig.shared.rates.relay
	local start: number = (PRESS + SINCE) % WIRE -- The keyframe's relay tick, the simulation tick's low bits at 20 Hz each
	local record: { [string]: any } = { slot = RIDER, generation = GENERATION, position = ABOARD, platform = PLATFORM }

	local ticks: { buffer } = {
		clip.keyframe({
			tick = start,
			characters = { { slot = RIDER, generation = GENERATION, kind = "Player", record = record } },
			platforms = { { id = PLATFORM, tick = PRESS } },
		}),
	}

	for index: number = 0, FRAMES - 1 do
		local tick: number = start + index
		table.insert(
			ticks,
			clip.frame({
				tick = tick,
				blocks = { { tick = tick, records = { record } } },
				owner = { slot = TARGET, generation = GENERATION, state = clip.state(vector.zero, tick), lag = 0 },
			})
		)
	end

	local playback: any = handle:play(ticks)
	playback:render(AHEAD / relay)

	local drawn: any = log.since(0)[RIDER]
	local platform: any = path(PRESS + SINCE + AHEAD, PRESS)
	local expected: vector = ABOARD + vector.create(platform.X, platform.Y, platform.Z)
	if drawn == nil then
		return false, "The rider wasn't drawn"
	elseif vector.magnitude(drawn.position - expected) > CLOSE then
		return false, `The rider was drawn at {drawn.position}, not on its platform's copy at {expected}`
	end

	playback:destroy()

	return true, nil
end
