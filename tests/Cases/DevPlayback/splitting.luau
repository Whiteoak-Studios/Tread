--[[
    A clip of a known size splits into parts each no larger than the
    server's part size, which stays inside the clip event's bound, and puts
    back together byte for byte, while a part missing or doubled is refused
--]]

--!strict
local Harness = require("../../Fixtures/DevClient/Harness")

local PARTS: string = "dev/Shared/ClipParts.luau"
local CONFIG: string = "dev/Server/Config/Clips.luau"
local EVENT_BYTES: number = 4096 -- The clip event's bytes, buffer(0..4096) in dev/Schemas/Dev.volt
local LENGTH_BYTES: number = 4 -- Each buffer's u32 length ahead of it in its list's run

-- A keyframe of 2,000 B and 40 frames of 200 B: 10,164 B with their lengths, and three withheld frames of 5 B
local KEYFRAME_BYTES: number = 2000
local FRAMES: number = 40
local FRAME_BYTES: number = 200
local WITHHELD: number = 3
local WITHHELD_BYTES: number = 5
local TICKS_BYTES: number = KEYFRAME_BYTES + FRAMES * FRAME_BYTES + (FRAMES + 1) * LENGTH_BYTES

-- A buffer of a length whose every byte follows from its list's seed and its place, so no two buffers match
local function filled(length: number, seed: number): buffer
	local data: buffer = buffer.create(length)
	for index: number = 0, length - 1 do
		buffer.writeu8(data, index, (seed * 31 + index * 7) % 256)
	end

	return data
end

-- Whether two lists hold the same buffers byte for byte, in the same order
local function same(given: { buffer }, back: { buffer }): boolean
	if #given ~= #back then
		return false
	end

	for index: number, data: buffer in given do
		if buffer.tostring(data) ~= buffer.tostring(back[index]) then
			return false
		end
	end

	return true
end

return function (): (boolean, string | nil)
	local place: Harness.Game = Harness.new()
	local ClipParts: any = place.load(PARTS)
	local size: number = place.load(CONFIG).partBytes

	if size > EVENT_BYTES then
		return false, `The server's part size of {size} B is past the clip event's {EVENT_BYTES} B`
	end

	local ticks: { buffer } = { filled(KEYFRAME_BYTES, 0) }
	for frame: number = 1, FRAMES do
		table.insert(ticks, filled(FRAME_BYTES, frame))
	end

	local withheld: { buffer } = {}
	for frame: number = 1, WITHHELD do
		table.insert(withheld, filled(WITHHELD_BYTES, FRAMES + frame))
	end

	local tickParts: { buffer } = ClipParts.split(ticks, size)
	local withheldParts: { buffer } = ClipParts.split(withheld, size)
	local emptyParts: { buffer } = ClipParts.split({}, size)

	-- 1) Each part no larger than the part size, every one full but the last, and the bytes all there
	local expected: number = math.ceil(TICKS_BYTES / size)
	if #tickParts ~= expected then
		return false, `{TICKS_BYTES} B split into {#tickParts} parts of {size} B, not {expected}`
	end

	local total: number = 0
	for index: number, part: buffer in tickParts do
		local length: number = buffer.len(part)
		total += length

		if length > size then
			return false, `Part {index} carries {length} B, past the part size of {size} B`
		elseif index < #tickParts and length ~= size then
			return false, `Part {index} of {#tickParts} carries {length} B, short of the part size of {size} B`
		end
	end

	if total ~= TICKS_BYTES then
		return false, `The parts carry {total} B of the run's {TICKS_BYTES} B`
	elseif #emptyParts ~= 1 or buffer.len(emptyParts[1]) ~= 0 then
		return false, "An empty list did not split into one empty part"
	end

	-- 2) Put back together byte for byte, ready only once both lists' last parts have arrived
	local assembly: any = ClipParts.new()
	for index: number, part: buffer in tickParts do
		local kept: boolean, refusal: string? = assembly:add(false, index, #tickParts, part)
		if not kept then
			return false, `Part {index} of the keyframe and frames was refused: {refusal}`
		elseif assembly:ready() then
			return false, `The assembly was ready after part {index} with no withheld part arrived`
		end
	end

	for index: number, part: buffer in withheldParts do
		assembly:add(true, index, #withheldParts, part)
	end

	if not assembly:ready() then
		return false, "The assembly was not ready with every part of both lists arrived"
	end

	local took: boolean, clip: any = assembly:take()
	if not took then
		return false, `The whole clip was refused: {clip}`
	elseif not same(ticks, clip.ticks) or not same(withheld, clip.withheld) then
		return false, "The clip did not come back byte for byte"
	end

	local empty: any = ClipParts.new()
	for index: number, part: buffer in tickParts do
		empty:add(false, index, #tickParts, part)
	end

	empty:add(true, 1, 1, emptyParts[1])
	local tookEmpty: boolean, emptyClip: any = empty:take()
	if not tookEmpty or #emptyClip.withheld ~= 0 or not same(ticks, emptyClip.ticks) then
		return false, "A clip with no withheld frames did not come back with an empty withheld list"
	end

	-- 3) A part missing is refused, naming it, once its list's last part has arrived
	local missing: any = ClipParts.new()
	for index: number, part: buffer in tickParts do
		if index ~= 2 then
			missing:add(false, index, #tickParts, part)
		end
	end

	missing:add(true, 1, 1, emptyParts[1])
	local tookMissing: boolean, missingReason: any = missing:take()
	if tookMissing then
		return false, "A clip with its second part missing was taken"
	elseif not tostring(missingReason):find(`part 2 of {#tickParts}`, 1, true) then
		return false, `The missing part's refusal did not name it: {missingReason}`
	end

	-- 4) A part doubled is refused and nothing kept, as is a part outside its total or one naming another total
	local doubled: any = ClipParts.new()
	doubled:add(false, 1, #tickParts, tickParts[1])

	local again: boolean = doubled:add(false, 1, #tickParts, tickParts[1])
	local past: boolean = doubled:add(false, #tickParts + 1, #tickParts, tickParts[1])
	local other: boolean = doubled:add(false, 2, #tickParts + 1, tickParts[2])
	if again or past or other then
		return false,
			`The assembly kept a doubled part ({again}), one past its total ({past}) or another total ({other})`
	end

	for index: number = 2, #tickParts do
		doubled:add(false, index, #tickParts, tickParts[index])
	end

	doubled:add(true, 1, 1, emptyParts[1])
	local tookDoubled: boolean, doubledClip: any = doubled:take()
	if not tookDoubled or not same(ticks, doubledClip.ticks) then
		return false, "The refused parts changed what the assembly put back together"
	end

	-- 5) The split refuses a size that is no whole number above 0, and a run past the event's 255 parts
	if pcall(ClipParts.split, ticks, 0) or pcall(ClipParts.split, ticks, 1.5) then
		return false, "The split took a part size of 0 B or 1.5 B"
	elseif pcall(ClipParts.split, { buffer.create(255 * 10) }, 10) then
		return false, "The split took a run that needs 256 parts"
	elseif not pcall(ClipParts.split, { buffer.create(255 * 10 - LENGTH_BYTES) }, 10) then
		return false, "The split refused a run that fits exactly 255 parts"
	end

	return true, nil
end
