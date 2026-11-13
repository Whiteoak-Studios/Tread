--[[
    A moderator's line pairs each read with the withheld second it covers,
    over the seconds all three lists hold, and gives in KB/s its copy and
    feed against 98, those less the target's own against 2, and the rest
--]]

--!strict
local Harness = require("../../Fixtures/DevServer/Harness")

-- Bytes a second. The fifth read has no withheld second beside it, so only four pair
local MODERATOR: { number } = { 100000, 110000, 105000, 120000, 999999 }
local WITHHELD: { number } = { 40000, 45000, 42000, 50000 }
local TARGET: { number } = { 58500, 63000, 61000, 69000, 1 }

-- Copy and feed 60, 65, 63 and 70 KB/s; less the target's own 1.5, 2, 2 and 1; by nearest rank of four
local LINE: string = "Moderator watching Target over 4 s, KB/s p50/p95/p99: copy and feed 63.00/70.00/70.00 against 98, "
	.. "less the target's own 1.50/2.00/2.00 against 2, "
	.. "withheld 42.00/50.00/50.00 outside the line beside about 71.5, the target's own 61.00/69.00/69.00"

return function (): (boolean, string | nil)
	local loaded: Harness.Loaded = Harness.load()
	local Spectators: any = loaded.require(loaded.game:GetService("ServerScriptService").Server.Spectators)

	local line: string = Spectators.line({
		moderator = "Moderator",
		target = "Target",
		moderatorBytes = MODERATOR,
		targetBytes = TARGET,
		withheld = WITHHELD,
	})

	if line ~= LINE then
		return false, `The moderator's line read "{line}", not "{LINE}"`
	end

	return true, nil
end
