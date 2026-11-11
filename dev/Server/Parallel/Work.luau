--[[
    What the parallel probe's workers and their pool share: the loop each
    runs, the topic a batch comes on, the attributes on a worker's Actor and
    the marks each worker writes into the marks table
--]]

--!strict
--!native
local MULTIPLIER: number = 31 -- Mixes each byte into the running total
local MODULUS: number = 65521 -- The largest prime under 2^16, which keeps the total small and whole

local Work = {
	TOPIC = "Work", -- A batch's message: its round, the loop's passes and the marks table

	-- The attributes on a worker's Actor
	WORKER = "Worker", -- Its index from 1, which only a clone the pool parents carries
	BOUND = "Bound", -- Set once it has bound the topic

	-- Its fields in the marks table, at (index - 1) * FIELDS plus each, the times by os.clock()
	START = 1,
	FINISH = 2,
	ROUND = 3, -- Written last, so its round there means both times are in
	FIELDS = 3,
}

--[[
    The probe's load, with no engine call: passes over the buffer, each
    byte mixed into a running total, which it returns
--]]

function Work.spin(data: buffer, passes: number): number
	local size: number = buffer.len(data)
	local total: number = 0

	for _ = 1, passes do
		for at: number = 0, size - 1 do
			total = (total * MULTIPLIER + buffer.readu8(data, at)) % MODULUS
		end
	end

	return total
end

return Work
