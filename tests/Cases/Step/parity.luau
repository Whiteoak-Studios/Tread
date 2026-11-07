--[[
    The step's parity run hashes to the constant its fixture holds, which
    the live scenario checks a Studio server's run against, and a run with
    one input's lowest bit flipped hashes to another
--]]

--!strict
local Environment = require("../../Environment")

local PARITY: string = "tests/Fixtures/Step/Parity.luau"

return function (): (boolean, string | nil)
	local Parity: any = Environment.load(PARITY)

	local hash: number = Parity.run(false)
	if hash ~= Parity.expected then
		return false, `the parity run hashed to {hash}, where its fixture holds {Parity.expected}`
	end

	local again: number = Environment.load(PARITY).run(false)
	if again ~= hash then
		return false, `a second parity run in a fresh environment hashed to {again}, where the first gave {hash}`
	end

	local flipped: number = Parity.run(true)
	if flipped == hash then
		return false, `the parity run with one bit flipped hashed to {flipped} too, so the hash tells nothing apart`
	end

	return true, nil
end
