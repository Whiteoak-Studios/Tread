--[[
    Fills a block's reveals from the cases' specs, { slot, generation, kind,
    past? }, each past { age, record } oldest first, its record the Record
    fields beside the reveal's slot and generation, laid out in pastData
--]]

--!strict
return function (block: any, specs: { any }, Record: any, Constants: any, limits: any)
	local entries: number = 0
	for _, spec: any in specs do
		entries += #(spec.past or {})
	end

	local data: buffer = buffer.create(math.max(entries, 1) * Constants.PAST_BYTES)
	local offset: number = 0
	local reveals: { any } = {}

	for index: number, spec: any in specs do
		local reveal: { [string]: any } = { slot = spec.slot, generation = spec.generation, kind = spec.kind }
		local past: { any }? = spec.past

		if past then
			reveal.pastCount, reveal.pastAt = #past, offset

			for _, entry: any in past do
				local record: { [string]: any } = Record.new()
				for name: string, value: any in entry.record do
					record[name] = value
				end

				record.slot, record.generation = spec.slot, spec.generation
				buffer.writeu8(data, offset, entry.age)
				Record.write(record, data, offset + 1, limits)
				offset += Constants.PAST_BYTES
			end
		end

		reveals[index] = reveal
	end

	block.reveals, block.revealCount, block.pastData = reveals, #reveals, data
end
