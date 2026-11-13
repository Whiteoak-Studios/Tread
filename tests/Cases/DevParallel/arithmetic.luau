--[[
    ParallelReturn's arithmetic with known answers: p50 and p95 by nearest
    rank in ms with the list left in order, shares to a tenth with none of
    none, and a return's piece lengths that hold its bytes end to end
--]]

--!strict
local Harness = require("../../Fixtures/DevServer/Harness")

local MS: number = 0.001
local PIECES: number = 250
local PIECE_BYTES: number = 1000 -- 1 KB over 250 pieces divides into 4 B each
local UNEVEN_BYTES: number = 10
local UNEVEN_PIECES: number = 4

return function (): (boolean, string | nil)
	local loaded: any = Harness.load()
	local Timings: any = loaded.require(loaded.game:GetService("ServerScriptService").Server.Parallel.Timings)

	-- 1) p50 by nearest rank of 3 is the 2nd lowest and p95 the 3rd, and the list keeps its order
	local samples: { number } = { 3 * MS, 1 * MS, 2 * MS }
	local spread: string = Timings.spread(samples)
	if spread ~= "p50 2.000 ms p95 3.000 ms" then
		return false, `Three samples spread as "{spread}"`
	elseif samples[1] ~= 3 * MS or samples[2] ~= 1 * MS then
		return false, "The spread sorted the samples it was handed"
	end

	local empty: string = Timings.spread({})
	if empty ~= "p50 0.000 ms p95 0.000 ms" then
		return false, `No samples spread as "{empty}"`
	end

	-- 2) Shares to a tenth, and a total of none gives 0 rather than a NaN
	local shares: string = `{Timings.share(1, 3)} {Timings.share(0, 0)} {Timings.share(2, 2)}`
	if shares ~= "33.3% 0.0% 100.0%" then
		return false, `1 of 3, 0 of 0 and 2 of 2 were shared as {shares}`
	end

	-- 3) Pieces that don't divide give their first ones the extra bytes, and those that do are all one length
	local uneven: string = table.concat(Timings.lengths(UNEVEN_BYTES, UNEVEN_PIECES), ",")
	if uneven ~= "3,3,2,2" then
		return false, `{UNEVEN_BYTES} B over {UNEVEN_PIECES} pieces gave lengths {uneven}`
	end

	local lengths: { number } = Timings.lengths(PIECE_BYTES, PIECES)
	local held: number = 0
	for _, length: number in lengths do
		if length ~= PIECE_BYTES / PIECES then
			return false, `{PIECE_BYTES} B over {PIECES} pieces gave a piece of {length} B`
		end

		held += length
	end

	if #lengths ~= PIECES or held ~= PIECE_BYTES then
		return false, `{PIECE_BYTES} B over {PIECES} pieces gave {#lengths} pieces holding {held} B`
	end

	return true, nil
end
