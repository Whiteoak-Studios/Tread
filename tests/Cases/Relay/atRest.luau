--[[
    Replication case 3, over Volt.mock: a viewer comes into range of a
    character at rest, gets its reveal at its resting place, the three rest
    repeats, then one record a second, and a hide when it despawns
--]]

--!strict
local Environment = require("../../Environment")

local HARNESS: string = "tests/Fixtures/Relay/Harness.luau"
local QUANTUM: number = 1 / 64
local RESTS: vector = vector.create(1200, 4, -30)
local INSIDE: vector = vector.create(400, 0, 0) -- Where the viewer walks to, 800 studs from it
local REPEAT_TICKS: number = 4 -- The far tier's tier ticks after the reveal hold its three repeats
local REPEATS: number = 3
local STILL_TICKS: number = 20 -- A second at the example's 20 Hz relay

return function (): (boolean, string | nil)
	local Harness: any = Environment.load(HARNESS)
	local harness: any = Harness.new(true)
	local client: any = harness:viewer("Viewer")
	local slot: number = harness:spawn("Player", RESTS)

	harness:runs(3)
	if next(client.drawn) ~= nil then
		return false, "A viewer 1,200 studs away was revealed the character"
	end

	client.viewer.position = INSIDE
	harness:run()

	local record: any = Harness.find(client.seen.records, slot)
	if Harness.count(client.seen.reveals, slot) ~= 1 or not record then
		return false, "Coming into range of a character at rest gave no reveal with its record"
	elseif vector.magnitude(record.position - RESTS) > QUANTUM then
		return false, `The reveal put the resting character at {record.position}, not at {RESTS}`
	end

	local repeats: number = 0
	for _ = 1, REPEAT_TICKS do
		harness:run()
		repeats += Harness.count(client.seen.records, slot)
	end

	if repeats ~= REPEATS then
		return false, `The resting character was repeated {repeats} times after its reveal, not {REPEATS}`
	end

	-- Then nothing for most of a second, and one record by the end of it
	local quiet: number? = nil
	for tick: number = 1, STILL_TICKS + REPEAT_TICKS do
		harness:run()

		if Harness.count(client.seen.records, slot) ~= 0 then
			quiet = tick
			break
		end
	end

	if quiet == nil or quiet < STILL_TICKS - REPEAT_TICKS then
		return false, `The still character's next record came {quiet} ticks after its repeats, not about a second`
	end

	harness:despawn(slot)
	harness:run()

	if Harness.count(client.seen.hides, slot) ~= 1 or client.drawn[slot] ~= nil then
		return false, "A character despawning in range gave the viewer no hide"
	elseif Harness.Relay.isSent(client.viewer.key, slot) then
		return false, "The viewer was still counted as sent a despawned character"
	end

	return true, nil
end
