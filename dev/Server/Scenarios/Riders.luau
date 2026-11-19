--[[
    Runs the riders' parity run on this server, the step's modules native as
    they ship, over an elevator and a mover on Lune's pure casts, which must
    hash to what Lune's own run gives, with a one-bit flip hashing apart
--]]

--!strict
local ServerScriptService = game:GetService("ServerScriptService")

local RiderParity = require(ServerScriptService.Fixtures.Step.RiderParity)

return function (): (boolean, string | nil)
	local hash: number = RiderParity.run(false)
	local flipped: number = RiderParity.run(true)
	print(`Riders parity: this server's hash {hash}, Lune's {RiderParity.expected}, flipped {flipped}`)

	if hash ~= RiderParity.expected then
		return false, `the riders' parity run hashed to {hash} here, where Lune's run gives {RiderParity.expected}`
	elseif flipped == hash then
		return false, `the riders' parity run with one bit flipped hashed to {flipped} too`
	end

	return true, nil
end
