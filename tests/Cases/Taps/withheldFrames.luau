--[[
    observeWithheld hands a target's sinks the withheld blocks its watchers
    were sent, each record with anti-ESP's reason, never an Invisible or Parked
    player, and frames with no block while no one watches the target
--]]

--!strict
local Environment = require("../../Environment")

local HARNESS: string = "tests/Fixtures/Relay/Harness.luau"
local TAP: string = "src/Codec/Tap.luau"
local BLOCK: string = "src/Codec/Block.luau"
local RECORD: string = "src/Codec/Record.luau"
local AWAY: vector = vector.create(4000, 0, 0) -- Past the target's relevancy, where the moderator stands
local LOOK: { [string]: any } = { head = 7, torso = 8 }
local RUNS: number = 4

--[[
    What a withheld frame's blocks carry: each record's reason by slot,
    whether each look entry holds a look by slot, how many look entries
    there are, and how many blocks
--]]

local function contents(
	Tap: any,
	Block: any,
	Record: any,
	data: buffer,
	limits: any
): ({ [number]: string }, { [number]: boolean }, number, number)
	local frame: any = Tap.read(data)
	local reasons: { [number]: string } = {}
	local looks: { [number]: boolean } = {}
	local entries: number = 0

	for _, part: any in frame.blocks do
		local block: any = Block.new()
		Block.read(part.data, block)

		for at: number = 1, block.recordCount do
			local record: any = Record.new()
			Record.read(part.data, block.records[at], record, limits)
			reasons[record.slot] = part.reasons[at]
		end

		for at: number = 1, block.lookCount do
			looks[block.looks[at].slot] = block.looks[at].look
			entries += 1
		end
	end

	return reasons, looks, entries, #frame.blocks
end

return function (): (boolean, string | nil)
	local Harness: any = Environment.load(HARNESS)
	local Tap: any = Environment.load(TAP)
	local Block: any = Environment.load(BLOCK)
	local Record: any = Environment.load(RECORD)

	local harness: any = Harness.new()
	local Taps: any = Harness.Taps
	local target: any = harness:viewer("Target")
	local moderator: any = harness:viewer("Moderator")
	moderator.viewer.position = AWAY

	local culled: number = harness:spawn("Player", vector.create(20, 0, 0))
	local untested: number = harness:spawn("Player", vector.create(-20, 0, 0))
	local invisible: number = harness:spawn("Player", vector.create(0, 0, 20))
	local parked: number = harness:spawn("Player", vector.create(0, 0, -20))
	local seen: number = harness:spawn("Player", vector.create(30, 0, 30))

	for _, slot: number in { culled, untested, invisible, parked } do
		harness:hide(target, slot, true)
	end

	harness:reason(target, culled, "Hidden")
	harness:reason(target, untested, "Untested")
	Harness.Relay.setLook(culled, LOOK)
	Harness.Relay.setInvisible(invisible, true)
	harness.states[parked].moveMode = "Parked"

	local frames: { buffer } = {}
	local stop: () -> () = Taps.observeWithheld(target.viewer.key, function (_: number, data: buffer)
		table.insert(frames, data)
	end)

	-- Nobody watches the target yet, so its frames hold no block
	harness:run()
	local _, _, _, blocks: number = contents(Tap, Block, Record, frames[1], harness.limits)
	if #frames ~= 1 or blocks ~= 0 then
		return false, `An unwatched target's withheld sink heard {#frames} frames with {blocks} blocks`
	end

	harness:watch(moderator, target)

	for run: number = 1, RUNS do
		harness:run()

		local reasons: { [number]: string }, looks: { [number]: boolean }, entries: number =
			contents(Tap, Block, Record, frames[run + 1], harness.limits)
		local records: { any }, sentLooks: { any } = Harness.withheld(moderator)

		local count: number = 0
		for _ in reasons do
			count += 1
		end

		if count ~= #records then
			return false, `Run {run}'s withheld frame holds {count} records, where the moderator was sent {#records}`
		elseif reasons[invisible] ~= nil or reasons[parked] ~= nil then
			return false, `Run {run}'s withheld frame held an Invisible or Parked player`
		elseif reasons[seen] ~= nil then
			return false, `Run {run}'s withheld frame held a player the target is sent`
		elseif entries ~= #sentLooks then
			return false,
				`Run {run}'s withheld frame carried {entries} look entries, where the moderator got {#sentLooks}`
		end

		for _, record: any in records do
			if reasons[record.slot] == nil then
				return false, `Run {run}'s withheld frame left out slot {record.slot}, which the moderator was sent`
			end
		end

		if run == 1 then
			if reasons[culled] ~= "Hidden" or reasons[untested] ~= "Untested" then
				return false, `The withheld records went with {reasons[culled]} and {reasons[untested]}`
			elseif not looks[culled] then
				return false, "The first withheld frame did not carry the culled player's look entry"
			end
		end
	end

	stop()
	harness:run()
	if #frames ~= RUNS + 1 or Taps.observing then
		return false, "A disconnected withheld sink heard a frame"
	end

	return true, nil
end
