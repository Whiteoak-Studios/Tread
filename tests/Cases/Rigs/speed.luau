--[[
    The pool's track speed: setSpeed gives every drawn rig's playing track
    the speed at once and every pose after it, a track a change of state
    plays runs at the speed though Play starts it at its own, a speed of 0
    holds it, and a climb held still stays still whatever the speed
--]]

--!strict
local roblox: any = require("@lune/roblox") -- Its typedefs leave out implementProperty and implementMethod

local Environment = require("../../Environment")

local ANIMATE: string = "src/Client/Rigs/Animate.luau"
local ANIMATE_PATH: string = "ReplicatedStorage.Packages.Tread.Client.Rigs.Animate" -- Where the pool requires it
local RIGS: string = "src/Client/Rigs/init.luau"
local RIG: string = "tests/Fixtures/Rigs/Rig.luau"
local STATE: string = "src/Step/State.luau"

local FULL: boolean = true
local SLOW: number = 0.5
local PAUSED: number = 0
local SLOT: number = 4
local DISTANCE: number = 10
local CLIMBING: vector = vector.create(0, 3, 0)
local AHEAD: vector = vector.create(0, 0, -10)

-- A stand-in AnimationTrack whose speed Play starts at its own and AdjustSpeed sets, each set written down
local function track(): any
	local fake: any = { IsPlaying = false, speed = 1, speeds = {} }

	fake.Play = function (self: any)
		self.IsPlaying = true
		self.speed = 1
	end

	fake.Stop = function (self: any, _: number?)
		self.IsPlaying = false
	end

	fake.AdjustSpeed = function (self: any, speed: number)
		self.speed = speed
		table.insert(self.speeds, speed)
	end

	return fake
end

return function (): (boolean, string | nil)
	-- 1) Animate: a change of track under a slowed pool plays at its speed, and a pause holds it
	local Animate = Environment.load(ANIMATE)
	local State = Environment.load(STATE)

	local tracks: { [string]: any } = { idle = track(), walk = track(), climb = track(), land = track() }
	local animated: any = {
		tracks = tracks,
		playing = nil,
		speed = 1,
		rate = 1,
		still = false,
		land = tracks.land,
		lands = nil,
	}

	local standing = State.new()
	standing.mode = "Ground"
	Animate.pose(animated, standing, FULL, SLOW)
	if tracks.idle.speed ~= SLOW then
		return false, `A track a change of state played under a speed of {SLOW} runs at {tracks.idle.speed}`
	end

	-- The walk that follows, played once the idle already ran slowed, runs slowed too
	local walking = State.new()
	walking.mode = "Ground"
	walking.velocity = AHEAD
	Animate.pose(animated, walking, FULL, SLOW)
	if tracks.walk.speed ~= SLOW then
		return false, `The next track a change of state played under a speed of {SLOW} runs at {tracks.walk.speed}`
	end

	Animate.speed(animated, PAUSED)
	if tracks.walk.speed ~= PAUSED then
		return false, `A speed of {PAUSED} left the playing track at {tracks.walk.speed}`
	end

	-- 2) A climb held still stays still under any speed, and climbs at the pool's speed once it moves
	local climbing = State.new()
	climbing.mode = "Ladder"
	Animate.pose(animated, climbing, FULL, SLOW)
	if tracks.climb.speed ~= PAUSED then
		return false, `A climb held still played at {tracks.climb.speed}`
	end

	climbing.velocity = CLIMBING
	Animate.pose(animated, climbing, FULL, SLOW)
	if tracks.climb.speed ~= SLOW then
		return false, `A moving climb under a speed of {SLOW} played at {tracks.climb.speed}`
	end

	-- 3) The pool: setSpeed reaches each drawn rig at once, and every pose after it passes the speed on. Lune's
	-- RunService has no PreSimulation and its Workspace no BulkMoveTo, which a drawn rig needs, and Lune takes one
	-- registration of each a run, so a case that ran first may have made it
	pcall(roblox.implementProperty, "RunService", "PreSimulation", function (_: any): any
		return {
			Connect = function (_: any, _: () -> ()): any
				return { Disconnect = function (_: any) end }
			end,
		}
	end)
	pcall(roblox.implementMethod, "Workspace", "BulkMoveTo", function (_: any, parts: { any }, cframes: { any }, _: any)
		for index: number, part: any in parts do
			part.CFrame = cframes[index]
		end
	end)

	local speeds: { number } = {}
	local posed: { number } = {}
	local Stub: { [string]: any } = {
		check = function (_: any) end,
		places = function (_: any, _: any): { any }
			return {}
		end,
		load = function (_: Model, _: any, _: any, _: any, _: any): any
			return { tracks = {} }
		end,
		detail = function (_: any, _: boolean) end,
		pose = function (_: any, _: any, _: boolean, speed: number?)
			table.insert(posed, speed or 1)
		end,
		speed = function (_: any, speed: number)
			table.insert(speeds, speed)
		end,
		aim = function (...: any) end,
		plant = function (...: any) end,
		layer = function (_: any) end,
		stop = function (_: any) end,
		watch = function (...: any) end,
		markers = function (_: any): { string }
			return {}
		end,
		release = function (_: any) end,
	}

	local Rigs = Environment.load(RIGS, { [ANIMATE_PATH] = Stub })
	local Rig = Environment.load(RIG)
	local rigs = Rigs.new(Rig.settings({}), Rig.drawDistance, Rig.collision())
	rigs:checkout(SLOT, {})
	rigs:pose(SLOT, standing, DISTANCE, 0)

	rigs:setSpeed(PAUSED)
	rigs:pose(SLOT, standing, DISTANCE, 0)
	if #speeds ~= 1 or speeds[1] ~= PAUSED then
		return false, `setSpeed({PAUSED}) reached the drawn rig {#speeds} times, with {speeds[1]}`
	elseif posed[#posed] ~= PAUSED then
		return false, `A pose after setSpeed({PAUSED}) passed a speed of {posed[#posed]}`
	end

	local refused: boolean = pcall(rigs.setSpeed, rigs, -1)
	if refused then
		return false, "setSpeed took a speed below 0"
	end

	rigs:destroy()

	return true, nil
end
