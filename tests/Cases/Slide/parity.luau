--[[
    The crouch slide's parity run slides, hashes to the constant its fixture
    holds, the same again in a fresh environment, and to another with one
    input's lowest bit flipped
--]]

--!strict
local Environment = require("../../Environment")

local PARITY: string = "tests/Fixtures/Step/SlideParity.luau"

return function (): (boolean, string | nil)
	local Parity: any = Environment.load(PARITY)

	local hash: number, slid: number = Parity.run(false)
	if slid == 0 then
		return false, "The parity run never slid, so its hash proves nothing about a slide"
	elseif hash ~= Parity.expected then
		return false, `The slide's parity run hashed to {hash}, where its fixture holds {Parity.expected}`
	end

	local again: number = Environment.load(PARITY).run(false)
	if again ~= hash then
		return false, `A second run in a fresh environment hashed to {again}, where the first gave {hash}`
	end

	local flipped: number = Parity.run(true)
	if flipped == hash then
		return false, `The run with one bit flipped hashed to {flipped} too, so the hash tells nothing apart`
	end

	return true, nil
end
