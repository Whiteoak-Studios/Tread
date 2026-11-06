--[[
    A relay block holds 55 records beside its header and refuses a 56th,
    holds 8 reveals each with its largest look entry and record and refuses a
    ninth, and refuses a section past its count or a look part past its bound
--]]

--!strict
local Environment = require("../../Environment")
local Refuses = require("../../Fixtures/Codec/Refuses")

local BLOCK: string = "src/Codec/Block.luau"
local LOOK: number = 64 -- The largest look and held item, in bytes
local HELD: number = 16

return function (): (boolean, string | nil)
	local Block: any = Environment.load(BLOCK)
	local data: buffer = buffer.create(1024)
	local pool: buffer = buffer.create(56 * 16)

	-- 55 records: the header and 888 B
	local records: { number } = {}
	for index: number = 1, 56 do
		buffer.writeu16(pool, (index - 1) * 16, index)
		records[index] = (index - 1) * 16
	end

	local block: any = Block.new()
	block.recordData, block.records, block.recordCount = pool, records, 55
	if Block.write(block, data) ~= 888 then
		return false, "55 records didn't fill the block's 888 B"
	end

	local exact: buffer = buffer.create(888)
	buffer.copy(exact, 0, data, 0, 888)
	local read: any = Block.new()
	Block.read(exact, read)
	if read.recordCount ~= 55 or buffer.readu16(exact, read.records[55]) ~= 55 then
		return false, `A block of 55 records read back {read.recordCount}, its last out of place`
	end

	block.recordCount = 56
	local refused: boolean, why: string = Refuses("passes its 896 B", Block.write, block, data)
	if not refused then
		return false, `A 56th record was written: {why}`
	end

	-- 8 reveals, each with a look entry of both parts at their largest and a record: 8 + 8 * 104 B
	local parts: buffer = buffer.create(LOOK + HELD)
	local function largest(count: number): any
		local made: any = Block.new()
		made.recordData = pool

		for index: number = 1, count do
			made.reveals[index] = { slot = index, generation = 1, kind = "Player" }
			made.looks[index] = {
				slot = index,
				generation = 1,
				look = true,
				lookData = parts,
				lookAt = 0,
				lookLength = LOOK,
				held = true,
				heldData = parts,
				heldAt = LOOK,
				heldLength = HELD,
			}
			made.records[index] = (index - 1) * 16
		end

		made.revealCount, made.lookCount, made.recordCount = count, count, count

		return made
	end

	if Block.write(largest(8), data) ~= 8 + 8 * 104 then
		return false, "8 reveals with their largest looks and records didn't fill 8 + 8 * 104 B"
	end

	refused, why = Refuses("passes its 896 B", Block.write, largest(9), data)
	if not refused then
		return false, `A ninth largest reveal was written: {why}`
	end

	-- A look part past its bound, and a section past the 255 its count holds
	local over: any = largest(1)
	over.looks[1].heldLength = HELD + 1
	refused, why = Refuses("held item is 0 to 16 B", Block.write, over, data)
	if not refused then
		return false, `A held item past 16 B was written: {why}`
	end

	over = largest(1)
	over.looks[1].lookLength = LOOK + 1
	refused, why = Refuses("look is 0 to 64 B", Block.write, over, data)
	if not refused then
		return false, `A look past 64 B was written: {why}`
	end

	local hides: any = Block.new()
	for index: number = 1, 256 do
		hides.hides[index] = { slot = index, generation = 0 }
	end

	hides.hideCount = 255
	if Block.write(hides, data) ~= 8 + 255 * 2 then
		return false, "255 hides didn't fill 8 + 510 B"
	end

	hides.hideCount = 256
	refused, why = Refuses("at most 255 entries", Block.write, hides, data)
	if not refused then
		return false, `256 hides were written: {why}`
	end

	-- A block written past its buffer
	refused, why = Refuses("passes its 896 B or its 100 B buffer", Block.write, largest(1), buffer.create(100))
	if not refused then
		return false, `A block past its buffer was written: {why}`
	end

	-- A reveal whose kind has no code
	local odd: any = largest(1)
	odd.reveals[1].kind = "Ghost"
	refused, why = Refuses("not Ghost", Block.write, odd, data)
	if not refused then
		return false, `A reveal of no kind was written: {why}`
	end

	return true, nil
end
