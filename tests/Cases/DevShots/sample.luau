--[[
    While shoot names a slot, the dev client's sample holds it, rests the
    movement and fires one shot every two ticks claiming the render time of
    the sample, counted from 0 each run; every other command carries none
--]]

--!strict
local Mount = require("../../Fixtures/DevShots/Mount")

local OWN: number = 9
local TARGET: number = 21
local GENERATION: number = 1
local FEET: vector = vector.create(0, 50, 0)
local FAR: number = -600 -- Studs along Z the target stands, four of the AKM's ticks of flight
local AKM: number = 1
local EVERY: number = 2
local START: number = 200 -- The relay tick the target's records start on
local BEFORE: number = 6 -- Frames drawn before firing starts
local FIRING: number = 24 -- Frames fired for
local AFTER: number = 10 -- Frames after firing stops, for the bullets in flight to resolve
local AGAIN: number = 4 -- Frames fired for in the second run
local RENDER_TICKS: number = 2 ^ 16
local FRACTION_STEPS: number = 256
local SEQUENCES: number = 64

-- The dev game's input as it samples, every movement input held and the shot list made once and never emptied
local function input(command: { [string]: any })
	command.forward = 1
	command.right = 0.5
	command.jump = true
	command.crouch = true
	command.sprint = true
	command.lean = 10
	command.fields.slot = 0

	if command.fields.shots == nil then
		command.fields.shots = {}
	end
end

-- Why one firing run's samples break the rule, or nil when they keep it
local function firingRun(run: { any }, slot: number): string?
	for index: number, sampled: any in run do
		local want: number = (index - 1) % EVERY == 0 and 1 or 0
		if #sampled.shots ~= want then
			return `Firing sample {index} carried {#sampled.shots} shots, not {want}`
		elseif sampled.slot ~= slot or sampled.moving then
			return `Firing sample {index} held slot {sampled.slot} and moving {sampled.moving}`
		end

		local shot: any = sampled.shots[1]
		if shot then
			local counter: number = (index - 1) // EVERY
			local whole: number = math.floor(sampled.renderTime)
			local fraction: number = math.floor((sampled.renderTime - whole) * FRACTION_STEPS)

			if shot.sequence ~= counter % SEQUENCES then
				return `Firing sample {index}'s shot was numbered {shot.sequence}, not {counter}`
			elseif shot.renderTick ~= whole % RENDER_TICKS or shot.fraction ~= fraction then
				local claimed: string = `{shot.renderTick} and {shot.fraction}`
				return `Firing sample {index} claimed {claimed}, not its own render time {sampled.renderTime}`
			end
		end
	end

	return nil
end

return function (): (boolean, string | nil)
	local mounted: Mount.Mounted = Mount.new({ input = input })
	local rig: any = mounted.rig

	rig.handshake()
	rig.own(OWN, GENERATION)
	rig.slots({ { slot = TARGET, generation = GENERATION, rig = "A" } })
	rig.owner(rig.body(FEET, 0, START))

	local frame: number = 0
	local lastShot: { [any]: boolean } = {} -- Whether each command table carried a shot when last sampled
	local reusedEmpty: boolean = false -- A command that carried a shot was sampled again while not firing a new one

	-- One frame: the target's record, then the server acknowledging the newest command, which frees the oldest to reuse
	local function step(count: number)
		for _ = 1, count do
			local tick: number = START + frame
			local reveals: { any }? = frame == 0 and { { slot = TARGET, generation = GENERATION, kind = "Player" } }
				or nil
			rig.relay({
				tick = tick,
				reveals = reveals,
				records = {
					{ slot = TARGET, generation = GENERATION, position = vector.create(0, FEET.y, FAR), yaw = 0 },
				},
			})

			local first: number = #mounted.sampled + 1
			rig.frames(1)

			for index: number = first, #mounted.sampled do
				local sampled: any = mounted.sampled[index]
				if lastShot[sampled.command] and #sampled.shots == 0 then
					reusedEmpty = true
				end

				lastShot[sampled.command] = #sampled.shots > 0
			end

			local moves: { any } = rig.moves
			local newest: any = moves[#moves]
			if newest then
				rig.owner(rig.body(FEET, newest.command, tick))
			end

			frame += 1
		end
	end

	step(BEFORE)
	local before: number = #mounted.sampled
	for index: number = 1, before do
		local sampled: any = mounted.sampled[index]
		if #sampled.shots ~= 0 or not sampled.moving or sampled.slot ~= 0 then
			return false, `Before shoot, sample {index} carried {#sampled.shots} shots in slot {sampled.slot}`
		end
	end

	-- 1) Firing: a shot every two samples from the first, slot held, movement at rest, the sample's own claim
	mounted.shoot(AKM)
	step(FIRING)
	local fired: { any } = table.move(mounted.sampled, before + 1, #mounted.sampled, 1, {})
	local failure: string? = firingRun(fired, AKM)
	if failure then
		return false, failure
	elseif #fired < FIRING / 2 then
		return false, `{FIRING} frames of firing made {#fired} samples`
	elseif not reusedEmpty then
		return false, "No command that carried a shot was sampled again, so reuse was never tried"
	end

	-- 2) Stopped: no new shot, while those in flight still report
	local shots: number = 0
	for _, sampled: any in fired do
		shots += #sampled.shots
	end

	local reportedAtStop: number = #mounted.reports
	mounted.shoot(0)
	local stopped: number = #mounted.sampled
	step(AFTER)

	for index: number = stopped + 1, #mounted.sampled do
		local sampled: any = mounted.sampled[index]
		if #sampled.shots ~= 0 or not sampled.moving then
			return false, `After shoot(0), sample {index - stopped} carried {#sampled.shots} shots or held the movement`
		end
	end

	if reportedAtStop >= shots then
		return false, "Every shot had reported by the stop, so none was left in flight to show it still reports"
	elseif #mounted.reports ~= shots then
		return false, `{shots} shots were fired and {#mounted.reports} reported`
	end

	for index: number, report: any in mounted.reports do
		if report.sequence ~= (index - 1) % SEQUENCES then
			return false, `Report {index} carried sequence {report.sequence}`
		end
	end

	-- 3) A second run counts from 0 again
	mounted.shoot(AKM)
	local again: number = #mounted.sampled
	step(AGAIN)
	local second: { any } = table.move(mounted.sampled, again + 1, #mounted.sampled, 1, {})
	failure = firingRun(second, AKM)
	if failure then
		return false, `In the second run: {failure}`
	end

	return true, nil
end
