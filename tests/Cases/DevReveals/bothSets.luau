--[[
    An unsent target is tested on both sets each tick: only a hull corner
    open counts hull reveals marked hull only and no body reveal, and a
    body point open counts both, the hull's not marked hull only
--]]

--!strict
local roblox: any = require("@lune/roblox") -- Its typedefs leave out the datatypes

local DevServer = require("../../Fixtures/DevServer/Harness")

local Vector3: any = roblox.Vector3
local CFrame: any = roblox.CFrame

local EYE: any = Vector3.new(0, 4.17, 0)
local FEET: any = Vector3.new(0, 0, -30) -- Straight ahead of the eye along -Z
local SIZE: any = Vector3.new(2.78, 5, 2.78) -- Frontier Zero's standing hull
local TOP_FRONT_LEFT: any = Vector3.new(-1, 1, -1) -- The corner left open, as a share of the hull's half size
local CORNER: number = 4 -- Its index in the hull's points
local HULL_CENTER: number = 1
local TORSO: number = 4 -- The body point left open, its index in the example's standing points
local READINGS: number = 2 -- Each set counts one reveal under each reading over the run
local CLOSE: number = 1e-4

-- A stand-in for anti-ESP's occlusion, open only to rays ending at one of the points given
local function openTo(points: { any }): (origin: vector, direction: vector) -> boolean
	return function (origin: vector, direction: vector): boolean
		local finish: vector = origin + direction

		for _, point: any in points do
			if vector.magnitude(finish - vector.create(point.X, point.Y, point.Z)) < CLOSE then
				return false
			end
		end

		return true
	end
end

-- A run's episodes in one set
local function inSet(found: { any }, set: string): { any }
	local episodes: { any } = {}
	for _, episode: any in found do
		if episode.set == set then
			table.insert(episodes, episode)
		end
	end

	return episodes
end

-- Why a set's episodes differ from one under each reading opened at a point and marked hull only or not, or nil
local function mismatch(episodes: { any }, set: string, point: number, only: boolean): string?
	if #episodes ~= READINGS then
		return `The {set} set counted {#episodes} episodes, not {READINGS}`
	end

	for _, episode: any in episodes do
		if episode.point ~= point or episode.hullOnly ~= only then
			local carried: string = `point {episode.point}, hull only {episode.hullOnly}`
			return `A {set} {episode.reading} episode carried {carried}, not point {point}, hull only {only}`
		end
	end

	return nil
end

return function (): (boolean, string | nil)
	local dev: DevServer.Loaded = DevServer.load()
	local services: any = dev.game:GetService("ServerScriptService")
	local Reveals: any = dev.require(services.Server.Reveals)
	local config: any = dev.require(services.Server.Config.Reveals)
	local harness: any = dev.require(services.Fixtures.AntiEsp.Harness).new()

	local center: any = FEET + Vector3.new(0, SIZE.Y / 2, 0)
	local box: { [string]: any } = { cframe = CFrame.new(center), size = SIZE }
	local target: { [string]: any } = {
		root = FEET,
		velocity = Vector3.zero,
		posture = "Stand",
		mode = "Ground",
		hullCenter = center,
		standingBox = box,
	}

	local inset: number = config.inset
	local corner: any = box.cframe * ((SIZE / 2 - Vector3.new(inset, inset, inset)) * TOP_FRONT_LEFT)
	local torsoUp: number = harness.server.antiEsp.aim.Stand[TORSO].up
	local torso: any = FEET + Vector3.new(0, torsoUp, 0)

	-- Ticks of the target unsent past the grace through a stand-in, each set tracked in a pair of its own
	local function run(blocked: (origin: vector, direction: vector) -> boolean): { any }
		local found: { any } = {}
		local sets: { { pair: any, seen: any } } = {
			{ pair = Reveals.pair(), seen = Reveals.sighting("body") },
			{ pair = Reveals.pair(), seen = Reveals.sighting("hull") },
		}

		for tick: number = 1, config.grace + 2 do
			for _, set: { pair: any, seen: any } in sets do
				set.seen.tick = tick
				set.seen.sent = false
				set.seen.reason = "Hidden"
			end

			Reveals.sight(sets[1].seen, sets[2].seen, EYE, target, blocked)

			for _, set: { pair: any, seen: any } in sets do
				Reveals.track(set.pair, set.seen, config.grace, found, "Viewer", "Target", false)
			end
		end

		return found
	end

	-- 1) Only the hull's top front left corner open: hull reveals, each hull only, and no body reveal
	local cornerOnly: { any } = run(openTo({ corner }))
	local bodies: { any } = inSet(cornerOnly, "body")
	if #bodies ~= 0 then
		return false, `With only a hull corner open the body set counted {#bodies} episodes`
	end

	local failure: string? = mismatch(inSet(cornerOnly, "hull"), "hull", CORNER, true)
	if failure then
		return false, `With only a hull corner open: {failure}`
	end

	-- 2) The torso's point open, and the hull's center: a body reveal there and hull reveals not hull only
	local bodyOpen: { any } = run(openTo({ torso, center }))
	failure = mismatch(inSet(bodyOpen, "body"), "body", TORSO, false)
		or mismatch(inSet(bodyOpen, "hull"), "hull", HULL_CENTER, false)
	if failure then
		return false, `With a body point open: {failure}`
	end

	local height: number = inSet(bodyOpen, "body")[1].height
	if math.abs(height - torsoUp) > CLOSE then
		return false, `The body reveal opened {height} studs up, not the torso's {torsoUp}`
	end

	return true, nil
end
