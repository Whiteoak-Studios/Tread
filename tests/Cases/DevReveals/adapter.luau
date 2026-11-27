--[[
    The adapter fills the four fields anti-ESP's aim reads from a public
    state, and anti-ESP aims at the adapted state's six ends the example's
    points give a standing target and a crouched one, with no look-ahead
--]]

--!strict
local roblox: any = require("@lune/roblox") -- Its typedefs leave out the datatypes

local DevServer = require("../../Fixtures/DevServer/Harness")

local Vector3: any = roblox.Vector3

local FEET: any = Vector3.new(5, 2, -20) -- Straight ahead of the eye along -Z
local VELOCITY: any = Vector3.new(12, 0, -9) -- Fast enough that any look-ahead would push the side ends out
local EYE: vector = vector.create(5, 6, 0)
local RIGHT: vector = vector.create(1, 0, 0) -- The viewer's right, looking along -Z
local POSTURES: { string } = { "Stand", "Crouch" }
local POINTS: number = 6 -- The ends each posture has in the example
local CLOSE: number = 1e-6

return function (): (boolean, string | nil)
	local dev: DevServer.Loaded = DevServer.load()
	local services: any = dev.game:GetService("ServerScriptService")
	local Reveals: any = dev.require(services.Server.Reveals)
	local Harness: any = dev.require(services.Fixtures.AntiEsp.Harness)
	local Public: any = dev.require(dev.game:GetService("ReplicatedStorage").Packages.Tread.Step.Public)

	local state: any = Public.new()
	state.root = FEET
	state.velocity = VELOCITY
	state.posture = "Stand"
	state.mode = "Ground"

	-- 1) The four fields, each the public state's, the positions on vector
	local feet: vector = vector.create(FEET.X, FEET.Y, FEET.Z)
	local velocity: vector = vector.create(VELOCITY.X, VELOCITY.Y, VELOCITY.Z)
	local adapted: { [string]: any } =
		{ position = vector.zero, velocity = vector.zero, posture = "Downed", mode = "Air" }

	Reveals.adapt(adapted, state)
	if adapted.position ~= feet or adapted.velocity ~= velocity then
		return false, `The adapter gave the feet {adapted.position} and the velocity {adapted.velocity}`
	elseif adapted.posture ~= "Stand" or adapted.mode ~= "Ground" then
		return false, `The adapter gave the posture {adapted.posture} and the mode {adapted.mode}`
	end

	-- 2) Anti-ESP started on the example's tables aims at each posture's points from the feet, sides to the right
	local harness: any = Harness.new()
	for _, posture: string in POSTURES do
		state.posture = posture
		Reveals.adapt(adapted, state)

		local ends: { vector } = {}
		local count: number = Harness.AntiEsp.aimPoints(EYE, adapted, ends)
		local points: { { [string]: any } } = harness.server.antiEsp.aim[posture]
		if count ~= POINTS or #points ~= POINTS then
			return false, `A {posture} target got {count} ends of the example's {#points}, not {POINTS}`
		end

		for index: number, point: { [string]: any } in points do
			local expected: vector = feet + RIGHT * point.side + vector.create(0, point.up, 0)
			if vector.magnitude(ends[index] - expected) > CLOSE then
				return false, `A {posture} target's end {index} sat at {ends[index]}, not {expected}`
			end
		end
	end

	return true, nil
end
