--[[
    observe hands a viewer's sinks one frame a relay tick, the same buffer to
    each: every block it was sent with each record's reason and its OwnerState,
    and a viewer sent nothing gets frames with neither
--]]

--!strict
local Environment = require("../../Environment")

local HARNESS: string = "tests/Fixtures/Relay/Harness.luau"
local TAP: string = "src/Codec/Tap.luau"
local BLOCK: string = "src/Codec/Block.luau"
local RECORD: string = "src/Codec/Record.luau"
local RUNS: number = 6
local OWNER_ID: number = 4097 -- Slot 1, generation 1
local OWNER_BYTES: number = 46 -- About Frontier Zero's OwnerState
local WRAP: number = 2 ^ 16

return function (): (boolean, string | nil)
	local Harness: any = Environment.load(HARNESS)
	local Tap: any = Environment.load(TAP)
	local Block: any = Environment.load(BLOCK)
	local Record: any = Environment.load(RECORD)

	-- Whole records, so each frame's block is the block the viewer was sent byte for byte
	local harness: any = Harness.new(false, function (_: any, server: any)
		server.relay.changes = false
	end)
	local Taps: any = Harness.Taps
	local client: any = harness:viewer("Viewer")
	local stranger: any = harness:viewer("Stranger")
	stranger.viewer.position = vector.create(5000, 0, 0)

	local mate: number = harness:spawn("Player", vector.create(10, 0, 0))
	local npc: number = harness:spawn("Npc", vector.create(0, 0, 20))
	local held: number = harness:spawn("Player", vector.create(-15, 0, 0))
	harness:reason(client, mate, "Teammate")
	harness:reason(client, npc, "Npc")
	harness:reason(client, held, "Hold")

	local expected: { [number]: string } = { [mate] = "Teammate", [npc] = "Npc", [held] = "Hold" }
	local frames: { { tick: number, data: buffer } } = {}
	local copies: { buffer } = {}
	local empties: { buffer } = {}

	if Taps.observing then
		return false, "The taps said a sink observed before any was connected"
	elseif pcall(Taps.observe, client.viewer.key, "sink") or pcall(Taps.observe, "viewer", print) then
		return false, "observe took a sink that is no function or a viewer that is no Player or bot"
	end

	local stopFirst: () -> () = Taps.observe(client.viewer.key, function (tick: number, data: buffer)
		table.insert(frames, { tick = tick, data = data })
	end)
	local stopSecond: () -> () = Taps.observe(client.viewer.key, function (_: number, data: buffer)
		table.insert(copies, data)
	end)
	local stopStranger: () -> () = Taps.observe(stranger.viewer.key, function (_: number, data: buffer)
		table.insert(empties, data)
	end)

	if not Taps.observing then
		return false, "The taps did not say a sink observed once one was connected"
	end

	local owner: buffer = buffer.create(OWNER_BYTES)
	for index: number = 0, OWNER_BYTES - 1 do
		buffer.writeu8(owner, index, index)
	end

	for run: number = 1, RUNS do
		-- The relay stage hands the OwnerState over on the first run alone
		if run == 1 then
			Taps.owner(client.viewer.key, OWNER_ID, owner)
		end

		harness.states[mate].position = vector.create(10 + run, 0, 0)
		harness:run()

		if #frames ~= run or #copies ~= run or #empties ~= run then
			return false, `After run {run} the sinks heard {#frames}, {#copies} and {#empties} frames, not {run} each`
		elseif frames[run].data ~= copies[run] then
			return false, `Run {run}'s two sinks were handed different buffers`
		elseif frames[run].tick ~= harness.tick then
			return false, `Run {run}'s sink was handed tick {frames[run].tick}, not {harness.tick}`
		end

		local frame: any = Tap.read(frames[run].data)
		local seen: any = client.seen
		if frame.tick ~= harness.tick % WRAP then
			return false, `Run {run}'s frame names tick {frame.tick}, not {harness.tick}`
		elseif #frame.blocks ~= #seen.sizes then
			return false, `Run {run}'s frame carries {#frame.blocks} blocks, where the viewer was sent {#seen.sizes}`
		end

		for index: number, part: any in frame.blocks do
			local block: any = Block.new()
			Block.read(part.data, block)

			if buffer.len(part.data) ~= seen.sizes[index] or block.sequence ~= seen.sequences[index] then
				return false, `Run {run}'s frame block {index} is not the block the viewer was sent`
			elseif #part.reasons ~= block.recordCount then
				return false,
					`Run {run}'s frame block {index} gives {#part.reasons} reasons for {block.recordCount} records`
			end

			for at: number = 1, block.recordCount do
				local record: any = Record.new()
				Record.read(part.data, block.records[at], record, harness.limits)

				if record.slot ~= seen.blocks[index].records[at] then
					return false, `Run {run}'s frame record {at} is not the one the viewer read`
				elseif part.reasons[at] ~= expected[record.slot] then
					return false,
						`Slot {record.slot}'s record went with {part.reasons[at]}, not {expected[record.slot]}`
				end
			end
		end

		local kept: any = frame.owner
		if
			run == 1 and (kept == nil or kept.id ~= OWNER_ID or buffer.tostring(kept.data) ~= buffer.tostring(owner))
		then
			return false, "The first frame did not carry the OwnerState handed over, with its character's id"
		elseif run > 1 and kept ~= nil then
			return false, `Run {run}'s frame carried an OwnerState though none was handed over`
		end

		local empty: any = Tap.read(empties[run])
		if #empty.blocks ~= 0 or empty.owner ~= nil or empty.tick ~= harness.tick % WRAP then
			return false, `Run {run} gave the viewer sent nothing a frame with blocks or an OwnerState`
		end
	end

	-- Every record went at least once over the runs, so each reason was carried
	local first: any = Tap.read(frames[1].data)
	if #first.blocks == 0 or #first.blocks[1].reasons ~= 3 then
		return false, "The first frame did not carry the three bodies' reveal records"
	end

	stopFirst()
	stopFirst()
	harness:run()
	if #frames ~= RUNS or #copies ~= RUNS + 1 then
		return false, "A disconnected sink heard a frame, or disconnecting one stopped its neighbor"
	end

	stopSecond()
	stopStranger()
	harness:run()
	if Taps.observing or #copies ~= RUNS + 1 or #empties ~= RUNS + 1 then
		return false, "With every sink disconnected the taps still observed or a sink still heard"
	end

	return true, nil
end
