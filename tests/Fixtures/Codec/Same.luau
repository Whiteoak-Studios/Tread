--[[
    Compares what a codec read back with what was written, table by table,
    and names the first place they differ, or gives nil when they match
--]]

--!strict

--[[
    Names the first key under path where actual differs from expected, a
    number or vector within tolerance of it and a buffer of the same bytes
    counting as the same, or nil
--]]

local function same(expected: any, actual: any, path: string, tolerance: number): string?
	if type(expected) == "table" then
		if type(actual) ~= "table" then
			return `{path} is {actual}, where a table was expected`
		end

		for key: any, value: any in expected do
			local differs: string? = same(value, actual[key], `{path}.{key}`, tolerance)
			if differs then
				return differs
			end
		end

		for key: any in actual do
			if expected[key] == nil then
				return `{path}.{key} is {actual[key]}, where nothing was expected`
			end
		end

		return nil
	elseif type(expected) == "number" and type(actual) == "number" then
		if math.abs(expected - actual) > tolerance then
			return `{path} is {actual}, where {expected} was expected`
		end

		return nil
	elseif type(expected) == "vector" and type(actual) == "vector" then
		if vector.magnitude(expected - actual) > tolerance then
			return `{path} is {actual}, where {expected} was expected`
		end

		return nil
	elseif type(expected) == "buffer" and type(actual) == "buffer" then
		if buffer.tostring(expected) ~= buffer.tostring(actual) then
			return `{path} holds other bytes than were expected`
		end

		return nil
	elseif expected ~= actual then
		return `{path} is {actual}, where {expected} was expected`
	end

	return nil
end

return function (expected: any, actual: any, path: string, tolerance: number?): string?
	return same(expected, actual, path, tolerance or 0)
end
