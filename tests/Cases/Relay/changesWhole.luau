--[[
    A record goes whole, a baseline in hand, when it rides with a reveal,
    when X moved past the 512 studs a change holds, for a new life in the
    slot, and to a new watcher, until its client acknowledges a copy
--]]

--!strict
local Environment = require("../../Environment")

local HARNESS: string = "tests/Fixtures/Relay/Harness.luau"
local CONSTANTS: string = "src/Constants.luau"
local STEP: vector = vector.create(0.5, 0, 0) -- What the target walks a run, so it has a record every run
local JUMP: vector = vector.create(600, 0, 0) -- Past the 512 studs an i16 of 1/64 stud holds, viewer and target alike
local LAG: number = 1 -- Runs the new life's reveal takes to be acknowledged

-- Whether a client's run carried the slot's one record whole, or why not
local function whole(Harness: any, client: any, slot: number, what: string): string?
	local records: number = Harness.count(client.seen.records, slot)
	if records ~= 1 then
		return `{what}: {records} records came, not 1`
	elseif Harness.find(client.seen.changes, slot) then
		return `{what}: the record came as a change`
	end

	return nil
end

-- Whether a client's run carried the slot's one record as a change, or why not
local function changed(Harness: any, client: any, slot: number, what: string): string?
	if Harness.count(client.seen.records, slot) ~= 1 or not Harness.find(client.seen.changes, slot) then
		return `{what}: the record did not come as a change`
	end

	return nil
end

return function (): (boolean, string | nil)
	local Harness: any = Environment.load(HARNESS)
	local slots: number = Environment.load(CONSTANTS).SLOTS
	local harness: any = Harness.new()
	local Relay: any = Harness.Relay
	local Slots: any = Harness.Slots

	local client: any = harness:viewer("Viewer")
	local slot: number = harness:spawn("Player", vector.create(10, 0, 0))
	local state: any = harness.states[slot]

	local function walk()
		state.position += STEP
		harness:run()
	end

	harness:run()
	walk()
	local problem: string? = changed(Harness, client, slot, "Walking after the acknowledged reveal")
	if problem then
		return false, problem
	end

	-- 1) A fresh reveal carries its record whole
	Relay.reveal(slot)
	walk()
	problem = whole(Harness, client, slot, "With a fresh reveal")
	if problem then
		return false, problem
	elseif Harness.count(client.seen.reveals, slot) ~= 1 then
		return false, "Relay.reveal sent no fresh reveal"
	end

	walk()
	problem = changed(Harness, client, slot, "After the fresh reveal was acknowledged")
	if problem then
		return false, problem
	end

	-- 2) X past what a change holds, the viewer moving with the target so it stays near
	state.position += JUMP
	client.viewer.position += JUMP
	harness:run()
	problem = whole(Harness, client, slot, "After a jump of 600 studs")
	if problem then
		return false, problem
	end

	walk()
	problem = changed(Harness, client, slot, "After the jump was acknowledged")
	if problem then
		return false, problem
	end

	-- 3) A new life in the same slot: every never-used slot taken, so the freed one comes back next
	local at: vector = state.position
	harness:despawn(slot)
	for _ = 1, slots - Slots.count("Player") - 1 do
		Slots.take("Player")
	end

	local again: number = harness:spawn("Player", at)
	if again ~= slot then
		return false, `The new life took slot {again}, not the freed {slot}`
	end

	state = harness.states[slot]
	client.lag = LAG

	for run: number = 1, LAG + 1 do
		walk()
		problem = whole(Harness, client, slot, `On run {run} of the new life`)
		if problem then
			return false, problem
		end
	end

	-- The harness's client finds no record of this life to decode a change against until it kept one
	walk()
	problem = changed(Harness, client, slot, "Once the new life's reveal was acknowledged")
	if problem then
		return false, problem
	end

	-- 4) A new watcher of the viewer, whose client holds none of its records, gets them whole with the viewer
	client.lag = 0
	table.clear(client.sent)
	walk()
	local moderator: any = harness:viewer("Moderator")
	moderator.viewer.position = vector.create(5000, 0, 0)
	harness:watch(moderator, client)

	walk()
	problem = whole(Harness, moderator, slot, "The new watcher's first copy")
		or whole(Harness, client, slot, "The viewer's block beside the new watcher's first copy")
	if problem then
		return false, problem
	end

	walk()
	problem = changed(Harness, moderator, slot, "Once the watcher acknowledged its first copy")
	if problem then
		return false, problem
	end

	return true, nil
end
