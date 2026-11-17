--[[
    The server calibration's loop on the client, compiled natively wherever
    the client supports it: passes over a buffer, each byte mixed into a
    running total, which it returns
--]]

--!strict
--!native
local MULTIPLIER: number = 31 -- Mixes each byte into the running total
local MODULUS: number = 65521 -- The largest prime under 2^16, which keeps the total small and whole

return function (data: buffer, passes: number): number
	local size: number = buffer.len(data)
	local total: number = 0

	for _ = 1, passes do
		for at: number = 0, size - 1 do
			total = (total * MULTIPLIER + buffer.readu8(data, at)) % MODULUS
		end
	end

	return total
end
