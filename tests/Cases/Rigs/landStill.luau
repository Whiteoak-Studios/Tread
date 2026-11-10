--[[
    A landing plays only into a still track on the ground: once when the
    land counter moves while idle, never while walking or sprinting, and it
    stops at the default fade once an idle landing turns into a walk
--]]

--!strict
local Environment = require("../../Environment")

local ANIMATE: string = "src/Client/Rigs/Animate.luau"
local STATE: string = "src/Step/State.luau"

local AHEAD: vector = vector.create(0, 0, -10)
local FULL: boolean = true -- Drawn inside lod.full, where a landing may play

-- The tracks these poses pick, beside the landing's own
local TRACKS: { string } = { "idle", "walk", "sprint", "land" }

-- A stand-in AnimationTrack that counts its plays and stops, with the fade its last stop was given
local function track(): any
	local fake: any = { IsPlaying = false, plays = 0, stops = 0, fade = nil }

	fake.Play = function (self: any)
		self.IsPlaying = true
		self.plays += 1
	end

	fake.Stop = function (self: any, fade: number?)
		self.IsPlaying = false
		self.stops += 1
		self.fade = fade
	end

	fake.AdjustSpeed = function (_: any, _: number) end

	return fake
end

return function (): (boolean, string | nil)
	local Animate = Environment.load(ANIMATE)
	local State = Environment.load(STATE)

	local tracks: { [string]: any } = {}
	for _, name: string in TRACKS do
		tracks[name] = track()
	end

	local land: any = tracks.land
	local animated: any = { tracks = tracks, playing = nil, land = land, lands = nil }

	local state = State.new()
	state.mode = "Ground"

	-- 1) Idle: the first pose reads the counter, and a move of it plays the landing once
	Animate.pose(animated, state, FULL)
	state.lands = 1
	Animate.pose(animated, state, FULL)
	if land.plays ~= 1 then
		return false, `A landing while idle played {land.plays} times, not once`
	end

	-- 2) The idle landing turning into a walk stops it, at the default fade
	state.velocity = AHEAD
	Animate.pose(animated, state, FULL)
	if land.IsPlaying or land.stops ~= 1 or land.fade ~= nil then
		return false, `A walk after an idle landing stopped it {land.stops} times with a fade of {land.fade}`
	end

	-- 3) Walking, then sprinting, a move of the counter plays nothing
	state.lands = 2
	Animate.pose(animated, state, FULL)
	if land.plays ~= 1 then
		return false, "A landing while walking played over the walk"
	end

	state.sprint = true
	state.lands = 3
	Animate.pose(animated, state, FULL)
	if land.plays ~= 1 then
		return false, "A landing while sprinting played over the sprint"
	end

	return true, nil
end
