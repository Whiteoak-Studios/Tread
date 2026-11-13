--[[
    The shooter's own view tests each segment against its targets moved
    back along their drawn velocity to the segment's time, and flies a
    bullet's later segments only once the render time reaches each one
--]]

--!strict
local roblox: any = require("@lune/roblox") -- Its typedefs leave out the datatypes

local Mount = require("../../Fixtures/DevShots/Mount")

local Vector3: any = roblox.Vector3

local OWN: number = 9
local TARGET: number = 21
local GENERATION: number = 1
local OWNER_TICK: number = 100
local FEET: vector = vector.create(0, 50, 0)

-- (a) Two records 5 ticks apart and 4.5 studs along X, so the target is drawn moving at exactly 18 studs/s
local FIRST: number = 100
local SECOND: number = 105
local STRIDE: number = 4.5
local SPRINT: number = 18
local BEHIND: number = 0.02 -- Seconds the segment's time lies before the render time the target is drawn at
local CHEST: number = 3.4 -- Studs over the feet, the middle of the standing chest capsule
local PASS: number = 0.85 -- Studs from the moved-back chest axis the line passes, inside its 0.9 radius
local SPAN: number = 20 -- Studs the line runs either way across the target

-- (b) A Bow shot at a target 90 studs off, crossing the line in segment 3's time
local BOW: number = 2
local AWAY: number = -90 -- Studs along Z the target stands
local STEP: number = 57 / 64 -- Studs along X it moves a tick, 17.8125 studs/s, exact at the record's 1/64 stud
local START: number = 200 -- The relay tick its records start on
local FRAMES: number = 40
local CROSSED: number = 3 -- The segment that strikes it

-- A target slot drawn from the records the case sends, beside the owner's own body
local function drawn(mounted: Mount.Mounted)
	local rig: any = mounted.rig
	rig.handshake()
	rig.own(OWN, GENERATION)
	rig.slots({ { slot = TARGET, generation = GENERATION, rig = "A" } })
	rig.owner(rig.body(FEET, 0, OWNER_TICK))
end

local function record(position: vector): { [string]: any }
	return { slot = TARGET, generation = GENERATION, position = position, yaw = 0 }
end

local function reveal(): { any }
	return { { slot = TARGET, generation = GENERATION, kind = "Player" } }
end

-- (a) A line 0.85 studs from the chest's axis once the target is moved back, and 1.21 from where it is drawn
local function movedBack(): (boolean, string?)
	local mounted: Mount.Mounted = Mount.new()
	local rig: any = mounted.rig
	drawn(mounted)

	local at: vector = vector.create(-30, FEET.y, -40)
	rig.relay({ tick = FIRST, reveals = reveal(), records = { record(at) } })
	rig.relay({ tick = SECOND, records = { record(at + vector.create(STRIDE, 0, 0)) } })
	rig.frames(2)

	local now: number = rig.handle:getRenderTime()
	local pose: any = rig.State.new()
	if not rig.Interpolate.pose(TARGET, pose) then
		return false, "The target was never drawn"
	elseif math.abs(pose.velocity.x - SPRINT) > 1e-9 or now <= FIRST or now >= SECOND then
		return false,
			`The target was drawn at {pose.velocity.x} studs/s at render time {now}, not {SPRINT} between its records`
	end

	local back: number = SPRINT * BEHIND -- 0.36 studs
	local x: number = pose.position.x - back - PASS
	local y: number = pose.position.y + CHEST
	local z: number = pose.position.z
	local from: any = Vector3.new(x, y, z + SPAN)
	local to: any = Vector3.new(x, y, z - SPAN)
	local due: number = now - BEHIND * rig.shared.rates.relay

	local struck: number? = mounted.Shots.strike(from, to, now, due)
	if struck ~= TARGET then
		return false, `The segment {BEHIND} s behind the drawn target struck {struck}, not slot {TARGET}`
	end

	-- The case has power only if the target as drawn, 1.21 studs off the line, is missed
	local unmoved: number? = mounted.Shots.strike(from, to, now, now)
	if unmoved ~= nil then
		return false, `The same line against the target as drawn struck {unmoved}, so moving it back proved nothing`
	end

	return true, nil
end

-- (b) One Bow shot, led onto where the target will be: the segment that reaches it strikes it at its own time
local function crossing(): (boolean, string?)
	local mounted: Mount.Mounted = Mount.new({ shots = { every = 2, spread = 0, seed = 1, lead = true } })
	local rig: any = mounted.rig
	drawn(mounted)

	local fired: any = nil
	for frame: number = 0, FRAMES do
		local tick: number = START + frame
		local position: vector = vector.create(-10 + STEP * frame, FEET.y, AWAY)
		rig.relay({ tick = tick, reveals = frame == 0 and reveal() or nil, records = { record(position) } })

		-- Firing starts once the target has been drawn a few frames, and stops after its first shot
		if frame == 4 then
			mounted.shoot(BOW)
		end

		rig.frames(1)

		if fired == nil then
			for _, sampled: any in mounted.sampled do
				if #sampled.shots > 0 then
					fired = sampled
					mounted.shoot(0)
					break
				end
			end
		end
	end

	if fired == nil then
		return false, "The shooter never fired"
	elseif #mounted.reports ~= 1 then
		return false, `{#mounted.reports} shots reported, not the one fired`
	end

	local shot: any = fired.shots[1]
	local claim: number = shot.renderTick + shot.fraction / 256
	local report: any = mounted.reports[1]
	local due: number = claim + CROSSED * rig.shared.rates.relay / rig.shared.rates.simulation

	if report.target ~= TARGET then
		return false, `The Bow's shot reported {report.target}, not the target it was led onto`
	elseif report.renderTime < due or report.renderTime >= due + 1 then
		return false, `It struck at render time {report.renderTime}, not in segment {CROSSED}'s, from {due}`
	end

	return true, nil
end

return function (): (boolean, string | nil)
	for _, part: () -> (boolean, string?) in { movedBack, crossing } do
		local passed: boolean, reason: string? = part()
		if not passed then
			return false, reason
		end
	end

	return true, nil
end
