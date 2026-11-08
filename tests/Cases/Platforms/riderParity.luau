--[[
    The riders' parity run hashes to the constant its fixture holds, which
    the Riders scenario checks a Studio server's run against, again in a
    fresh environment, and a run with one input's lowest bit flipped
    hashes to another
--]]

--!strict
local Environment = require("../../Environment")

local RIDERS: string = "tests/Fixtures/Step/RiderParity.luau"

return function (): (boolean, string | nil)
	local Riders: any = Environment.load(RIDERS)

	local hash: number = Riders.run(false)
	if hash ~= Riders.expected then
		return false, `The riders' parity run hashed to {hash}, where its fixture holds {Riders.expected}`
	end

	local again: number = Environment.load(RIDERS).run(false)
	if again ~= hash then
		return false, `A second run in a fresh environment hashed to {again}, where the first gave {hash}`
	end

	local flipped: number = Riders.run(true)
	if flipped == hash then
		return false, `The run with one bit flipped hashed to {flipped} too, so the hash tells nothing apart`
	end

	-- The run rides both platforms, leaves one and boards the other
	local trace: { { number } } = {}
	Riders.run(false, trace)

	local seen: { [number]: boolean } = {}
	for _, values: { number } in trace do
		seen[values[11]] = true
	end

	if not (seen[0] and seen[Riders.elevator] and seen[Riders.mover]) then
		return false, "The riders' parity run never rode the elevator, never left it, or never rode the mover"
	end

	return true, nil
end
