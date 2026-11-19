--[[
    What the parallel probes' workers and their pools share: the topics a
    worker binds, the attributes on its Actor and the marks it writes, the
    loops it runs, and how a value that crossed between VMs is described
--]]

--!strict
--!native
local MULTIPLIER: number = 31 -- Mixes each byte into the running total
local MODULUS: number = 65521 -- The largest prime under 2^16, which keeps the total small and whole
local SEPARATOR: string = ", " -- Between a table's entries, and between its description and its flags

local Work = {
	TOPIC = "Work", -- A batch's message: its round, the loop's passes and the marks table

	-- ParallelReturn's messages, each but the arm's handled desynchronized
	TIMING = "Timing", -- P1's round: its number, the spin in seconds, the worker's event and the marks table
	ARM = "Arm", -- Starts the ConnectParallel arm: its event and the marks table
	ECHO = "Echo", -- P4's value: its label, the worker's event and the value, last since it may be nil
	STORE = "Store", -- P4's SharedTable writes: the worker's event, the SharedTable and the bytes of each value
	SEND = "Send", -- P5's send: its round, the marks table and the payload, which the worker leaves unread
	RETURN = "Return", -- P5's event return: its round, its bytes, the event to fire and the marks table
	SHARE = "Share", -- P5's SharedTable return: its round, its bytes and the marks table it writes the string into

	-- The attributes on a worker's Actor
	WORKER = "Worker", -- Its index from 1, which only a clone the pool parents carries
	BOUND = "Bound", -- Set once it has bound every topic

	-- Its fields in the marks table, at (index - 1) * FIELDS plus each, the times by os.clock()
	START = 1,
	FINISH = 2,
	ROUND = 3, -- Written last, so its round there means both times are in
	FIELDS = 3,

	-- Named keys in a marks table or P4's SharedTable
	FRAME = "Frame", -- The main thread's PreSimulation count, which the arm reads
	TEXT = "Text", -- A string a worker wrote
	BUFFER = "Buffer", -- A buffer a worker wrote

	MARK = 1, -- The byte a worker writes first in a buffer it was sent, so the main thread can tell a copy
	FILL = "x", -- What the probes' strings are made of
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

-- Holds the thread busy for that many seconds by os.clock(), with no engine call, giving how often it read the clock
function Work.busy(seconds: number): number
	local finish: number = os.clock() + seconds
	local reads: number = 0

	repeat
		reads += 1
	until os.clock() >= finish

	return reads
end

--[[
    What a value arrived as: a buffer or string by its bytes, an Instance by
    its class, a table by its entries sorted, then whether it is frozen and
    has a metatable, and anything else by its type and its text
--]]

function Work.describe(value: unknown): string
	if value == nil then
		return "nil"
	elseif type(value) == "buffer" then
		return `buffer of {buffer.len(value)} B`
	elseif type(value) == "string" then
		return `string of {#value} B`
	elseif typeof(value) == "Instance" then
		return `Instance of class {(value :: Instance).ClassName}`
	elseif type(value) ~= "table" then
		return `{typeof(value)} {tostring(value)}`
	end

	local entries: { [unknown]: unknown } = value :: { [unknown]: unknown }
	local described: { string } = {}
	for key: unknown, entry: unknown in entries do
		table.insert(described, `{tostring(key)}: {Work.describe(entry)}`)
	end

	table.sort(described)

	local parts: { string } = { `table ({table.concat(described, SEPARATOR)})` }
	if table.isfrozen(entries) then
		table.insert(parts, "frozen")
	end

	if getmetatable(entries) ~= nil then
		table.insert(parts, "with a metatable")
	end

	return table.concat(parts, SEPARATOR)
end

return Work
