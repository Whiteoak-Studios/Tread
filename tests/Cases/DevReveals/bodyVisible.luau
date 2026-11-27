--[[
    The body set's test casts from the eye to each aim end in order: every
    ray blocked but one shows the target at that point with none cast past
    it, and every ray blocked hides it after the count's rays alone
--]]

--!strict
local Harness = require("../../Fixtures/DevServer/Harness")

local EYE: vector = vector.create(0, 4, 0)

-- A standing target's six ends 20 studs ahead along -Z, as anti-ESP places them
local ENDS: { vector } = {
	vector.create(0, 5, -20),
	vector.create(-1.4, 4, -20),
	vector.create(1.4, 4, -20),
	vector.create(0, 3, -20),
	vector.create(-0.5, 1, -20),
	vector.create(0.5, 1, -20),
}

local OPEN: number = 3 -- The one end left open, a right shoulder
local FEWER: number = 2 -- A count that stops before it
local CLOSE: number = 1e-6

-- One ray the stand-in was asked about
type Ray = { origin: vector, direction: vector }

-- A stand-in for anti-ESP's occlusion that blocks every ray but the one to the end given, and keeps each ray
local function blockedBut(open: vector?, rays: { Ray }): (origin: vector, direction: vector) -> boolean
	return function (origin: vector, direction: vector): boolean
		table.insert(rays, { origin = origin, direction = direction })

		return open == nil or vector.magnitude(origin + direction - open) > CLOSE
	end
end

-- Why the rays cast differ from one from the eye to each of the first count ends in order, or nil when they match
local function mismatch(rays: { Ray }, count: number): string?
	if #rays ~= count then
		return `{#rays} rays were cast, not {count}`
	end

	for index: number, ray: Ray in rays do
		if ray.origin ~= EYE or vector.magnitude(ray.direction - (ENDS[index] - EYE)) > CLOSE then
			return `Ray {index} ran from {ray.origin} along {ray.direction}, not from the eye to end {index}`
		end
	end

	return nil
end

return function (): (boolean, string | nil)
	local loaded: Harness.Loaded = Harness.load()
	local Reveals: any = loaded.require(loaded.game:GetService("ServerScriptService").Server.Reveals)

	-- 1) Every ray blocked: hidden, after all six
	local covered: { Ray } = {}
	local visible: boolean, rays: number = Reveals.bodyVisible(EYE, ENDS, #ENDS, blockedBut(nil, covered))
	local failure: string? = mismatch(covered, #ENDS)
	if visible or rays ~= #ENDS or failure then
		return false, `A covered body read visible {visible} after {rays} rays: {failure}`
	end

	-- 2) Every ray blocked but the third: visible there, and none cast past it
	local showing: { Ray } = {}
	visible, rays = Reveals.bodyVisible(EYE, ENDS, #ENDS, blockedBut(ENDS[OPEN], showing))
	failure = mismatch(showing, OPEN)
	if not visible or rays ~= OPEN or failure then
		return false, `A body open at end {OPEN} read visible {visible} at {rays}: {failure}`
	end

	-- 3) A count short of the open end: hidden, after that many rays
	local short: { Ray } = {}
	visible, rays = Reveals.bodyVisible(EYE, ENDS, FEWER, blockedBut(ENDS[OPEN], short))
	failure = mismatch(short, FEWER)
	if visible or rays ~= FEWER or failure then
		return false, `A count of {FEWER} read visible {visible} after {rays} rays: {failure}`
	end

	return true, nil
end
