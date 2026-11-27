--[[
    Replication case 2, over Volt.mock: a character moving toward a viewer
    is sent nothing past the 950-stud entry, is revealed with its record at
    its place on the tick it crosses it, and keeps reaching it at far rate
--]]

--!strict
local Environment = require("../../Environment")

local HARNESS: string = "tests/Fixtures/Relay/Harness.luau"
local QUANTUM: number = 1 / 64
local ENTER: number = 950 -- The example's relevancy.enter
local START: number = 1100
local SPEED: number = 20 -- Studs it closes a tick
local AFTER: number = 8 -- Ticks counted after the reveal, at the far tier's 15 Hz of a 20 Hz relay
local FAR_RECORDS: number = 6

return function (): (boolean, string | nil)
	local Harness: any = Environment.load(HARNESS)
	local harness: any = Harness.new(true)
	local client: any = harness:viewer("Viewer")
	local slot: number = harness:spawn("Player", vector.create(START, 0, 0))

	local x: number = START
	local revealed: boolean = false

	while not revealed do
		x -= SPEED
		harness.states[slot].position = vector.create(x, 0, 0)
		harness:run()

		local seen: any = client.seen
		if x > ENTER then
			if #seen.reveals + #seen.records ~= 0 then
				return false, `The character was sent at {x} studs, past the {ENTER}-stud entry`
			end
		else
			local record: any = Harness.find(seen.records, slot)
			if Harness.count(seen.reveals, slot) ~= 1 or not record then
				return false, `Crossing to {x} studs gave no reveal with its record`
			elseif math.abs(record.position.x - x) > QUANTUM then
				return false, `The reveal put the character at {record.position.x}, not where it is, {x}`
			end

			revealed = true
		end
	end

	local records: number = 0
	for _ = 1, AFTER do
		x -= SPEED
		harness.states[slot].position = vector.create(x, 0, 0)
		harness:run()

		local record: any = Harness.find(client.seen.records, slot)
		if record then
			records += 1

			if math.abs(record.position.x - x) > QUANTUM then
				return false, `A record put the moving character at {record.position.x}, not at {x}`
			end
		end
	end

	if records ~= FAR_RECORDS then
		return false, `The far character was sent {records} records in {AFTER} ticks, where 15 Hz sends {FAR_RECORDS}`
	end

	return true, nil
end
