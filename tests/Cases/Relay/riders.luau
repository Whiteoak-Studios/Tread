--[[
    A rider's record carries its platform's id and its place less where the
    platform stands at the tick, so a rider carried by a moving lift sends
    nothing new, while with no platforms handed in every record stays in
    world space with platform 0, as does a rider of a platform not handed in
--]]

--!strict
local Environment = require("../../Environment")

local HARNESS: string = "tests/Fixtures/Relay/Harness.luau"
local PLATFORM: number = 5
local OTHER: number = 9 -- A platform the tick's table holds no place for
local LIFT: vector = vector.create(90, 8, 40)
local ABOVE: vector = vector.create(10, 2, 10) -- The rider's place on the lift
local RISE: vector = vector.create(0, 0.25, 0) -- The lift's move a tick
local WALKER: vector = vector.create(-30, 0, 0)
local STRAY: vector = vector.create(0, 0, -40)
local QUANTUM: number = 1 / 32 -- The record's coarsest axis, Y
local REST: number = 4 -- The reveal and its three rest repeats
local TICKS: number = 12

-- Whether a record read back sits within a quantum of a place
local function near(record: any, at: vector): boolean
	return vector.magnitude(record.position - at) <= QUANTUM
end

return function (): (boolean, string | nil)
	local Harness: any = Environment.load(HARNESS)
	local harness: any = Harness.new()
	local client: any = harness:viewer("Viewer")

	local rider: number = harness:spawn("Player", LIFT + ABOVE)
	local walker: number = harness:spawn("Player", WALKER)
	local stray: number = harness:spawn("Player", STRAY)
	harness.states[rider].platform = PLATFORM
	harness.states[stray].platform = OTHER

	-- With no platforms handed in, the rider is in world space with platform 0
	harness:run()

	local record: any = Harness.find(client.seen.records, rider)
	if not record or record.platform ~= 0 or not near(record, LIFT + ABOVE) then
		return false, "With no platforms handed in, the rider's record was not in world space with platform 0"
	end

	-- With them, the rider is in its platform's space, and the walker and the stray rider stay in world space
	local lift: vector = LIFT
	harness.platforms = { [PLATFORM] = lift }
	harness:run()

	record = Harness.find(client.seen.records, rider)
	if not record or record.platform ~= PLATFORM or not near(record, ABOVE) then
		return false, "The rider's record was not its place on platform 5 less the platform's place"
	end

	local walked: any = Harness.find(client.seen.records, walker)
	local strayed: any = Harness.find(client.seen.records, stray)
	if walked and (walked.platform ~= 0 or not near(walked, WALKER)) then
		return false, "A body on no platform had its record moved off world space"
	elseif strayed and (strayed.platform ~= 0 or not near(strayed, STRAY)) then
		return false, "A rider of a platform not handed in had its record put in a platform's space"
	end

	-- The lift rises with its rider aboard, and once the rest repeats are spent no record goes
	local sent: number = 0
	for _ = 1, TICKS do
		lift += RISE
		harness.platforms[PLATFORM] = lift
		harness.states[rider].position = lift + ABOVE
		harness:run()

		for _, seen: any in client.seen.records do
			if seen.slot == rider then
				sent += 1

				if seen.platform ~= PLATFORM or not near(seen, ABOVE) then
					return false, "A moving lift's rider was sent a record off its place on the lift"
				end
			end
		end
	end

	if sent >= REST then
		return false, `A rider standing still on a moving lift was sent {sent} records in {TICKS} ticks`
	end

	return true, nil
end
