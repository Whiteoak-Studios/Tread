--[[
    A recorded clip's two lists cut into the parts the dev scope's clip
    event carries, each list's buffers run together behind their lengths,
    and put back together on the client, refusing a part missing or doubled
--]]

--!strict
local ClipParts = {}
ClipParts.__index = ClipParts

local LENGTH_BYTES: number = 4 -- Each buffer's u32 length, ahead of its bytes in its list's run
local MAX_PARTS: number = 255 -- The clip event's u8 index and total hold no more

-- The two lists client:play takes
export type Clip = {
	ticks: { buffer }, -- The keyframe, then the observed frames, oldest first
	withheld: { buffer }, -- The withheld frames over the same ticks
}

-- One list's parts as they arrive, by index
type List = {
	total: number,
	parts: { [number]: buffer },
}

type Fields = {
	_ticks: List?, -- nil until the list's first part arrives
	_withheld: List?,
}

-- What a refusal calls a list
local function nameOf(withheld: boolean): string
	return withheld and "withheld frames" or "keyframe and frames"
end

--[[
    Runs a list's buffers together, each behind its u32 length, and cuts
    the run into parts of at most size bytes, in order. An empty list still
    gives one empty part, so the client hears of every list. It errors on a
    size that is no whole number above 0, and on a run past 255 parts
--]]

function ClipParts.split(list: { buffer }, size: number): { buffer }
	if not (size >= 1) or size % 1 ~= 0 then
		error(`ClipParts.split cuts parts of a whole number of bytes above 0, not {size}`, 2)
	end

	local bytes: number = 0
	for _, data: buffer in list do
		bytes += LENGTH_BYTES + buffer.len(data)
	end

	local count: number = math.max(math.ceil(bytes / size), 1)
	if count > MAX_PARTS then
		error(`ClipParts.split's run of {bytes} B needs {count} parts of {size} B, past the event's {MAX_PARTS}`, 2)
	end

	local run: buffer = buffer.create(bytes)
	local at: number = 0
	for _, data: buffer in list do
		buffer.writeu32(run, at, buffer.len(data))
		buffer.copy(run, at + LENGTH_BYTES, data)
		at += LENGTH_BYTES + buffer.len(data)
	end

	local parts: { buffer } = {}
	for index: number = 1, count do
		local from: number = (index - 1) * size
		local part: buffer = buffer.create(math.min(size, bytes - from))
		buffer.copy(part, 0, run, from, buffer.len(part))
		parts[index] = part
	end

	return parts
end

--[[
    An assembly of one clip's parts, none arrived yet
--]]

function ClipParts.new(): Self
	return setmetatable({
		_ticks = nil :: List?,
		_withheld = nil :: List?,
	}, ClipParts)
end

--[[
    Keeps one part as it arrives, refusing, with nothing kept, an index
    outside its list's total, a total other than the list's first part
    gave, and a part of its list already kept
--]]

function ClipParts.add(
	self: Self,
	withheld: boolean,
	index: number,
	total: number,
	data: buffer
): (boolean, string | nil)
	local name: string = nameOf(withheld)
	if not (index >= 1 and index <= total) or index % 1 ~= 0 then
		return false, `part {index} of {total} of the {name} lies outside its list`
	end

	local kept: List? = self._ticks
	if withheld then
		kept = self._withheld
	end

	local list: List = kept or { total = total, parts = {} }
	if list.total ~= total then
		return false, `part {index} of the {name} gives {total} parts, where the list's first gave {list.total}`
	elseif list.parts[index] ~= nil then
		return false, `part {index} of {total} of the {name} came twice`
	end

	list.parts[index] = data

	if withheld then
		self._withheld = list
	else
		self._ticks = list
	end

	return true, nil
end

--[[
    Whether both lists' last parts have arrived, after which take gives
    the clip or names the part missing, since the event's parts arrive in
    the order sent
--]]

function ClipParts.ready(self: Self): boolean
	local ticks: List? = self._ticks
	local withheld: List? = self._withheld
	if not ticks or not withheld then
		return false
	end

	return ticks.parts[ticks.total] ~= nil and withheld.parts[withheld.total] ~= nil
end

-- One list's buffers from its parts run back together, or what refuses it
local function join(list: List?, name: string): (boolean, string | { buffer })
	if not list then
		return false, `no part of the {name} has arrived`
	end

	local bytes: number = 0
	for index: number = 1, list.total do
		local part: buffer? = list.parts[index]
		if not part then
			return false, `part {index} of {list.total} of the {name} is missing`
		end

		bytes += buffer.len(part)
	end

	local run: buffer = buffer.create(bytes)
	local at: number = 0
	for index: number = 1, list.total do
		local part: buffer = list.parts[index]
		buffer.copy(run, at, part)
		at += buffer.len(part)
	end

	-- Each pass reads at least a length, so the walk ends at the run's end
	local buffers: { buffer } = {}
	at = 0
	while at < bytes do
		if at + LENGTH_BYTES > bytes then
			return false, `the {name} end partway through a buffer's length`
		end

		local length: number = buffer.readu32(run, at)
		at += LENGTH_BYTES
		if at + length > bytes then
			return false, `the {name} end partway through a buffer of {length} B`
		end

		local data: buffer = buffer.create(length)
		buffer.copy(data, 0, run, at, length)
		table.insert(buffers, data)
		at += length
	end

	return true, buffers
end

--[[
    The clip its parts make once ready, refusing a list with no part or
    a part missing, and one whose bytes end partway through a buffer. The
    assembly keeps what it holds either way
--]]

function ClipParts.take(self: Self): (boolean, string | Clip)
	local tookTicks: boolean, ticks: string | { buffer } = join(self._ticks, nameOf(false))
	if not tookTicks then
		return false, ticks :: string
	end

	local tookWithheld: boolean, withheld: string | { buffer } = join(self._withheld, nameOf(true))
	if not tookWithheld then
		return false, withheld :: string
	end

	local clip: Clip = { ticks = ticks :: { buffer }, withheld = withheld :: { buffer } }

	return true, clip
end

export type ClipParts = Self
type Self = typeof(setmetatable({} :: Fields, ClipParts))

return ClipParts
