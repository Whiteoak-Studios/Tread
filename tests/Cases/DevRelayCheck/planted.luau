--[[
    The relay check's comparison finds nothing between two copies' records
    that match, and names the layout, run, recipient and first differing
    byte of a block planted one byte apart, a block missing and a query
--]]

--!strict
local Harness = require("../../Fixtures/DevServer/Harness")

local LAYOUT: string = "fight"
local RUN: number = 7
local BLOCK: string = "\1\2\3\4\5\6\7\8" -- A block's bytes, which the planted one differs from at byte 5
local PLANTED: string = "\1\2\3\4\5\0\7\8"

local MATCHED: string =
	"fight run 7, block to fight2 2 first differs at byte 5 of 8 and 8 B, 6 serially, 0 on the workers"
local MISSING: string = "fight run 7, withheld block to Moderator: 1 serially and 0 on the workers"
local QUERY: string = "fight run 7, counts first differs at byte 3 of 7 and 7 B, 52 serially, 53 on the workers"

-- One copy's record of a run: two blocks to one viewer, one to another, a withheld block, asks, a frame and queries
local function record(): any
	return {
		blocks = { fight1 = { "\9\9" }, fight2 = { "\3\3", BLOCK } },
		withheld = { Moderator = { "\5" } },
		asks = { fight1 = { "4", "7" } },
		frames = { fight1 = { "\0\1" } },
		queries = { counts = "12 4 30", ["isSent of fight1 by slot"] = "0110" },
	}
end

local function summary(): any
	return {
		layout = LAYOUT,
		runs = 0,
		blocks = 0,
		withheld = 0,
		frames = 0,
		asks = 0,
		reveals = 0,
		hides = 0,
		calls = {},
		mismatches = {},
		found = 0,
	}
end

return function (): (boolean, string | nil)
	local loaded: Harness.Loaded = Harness.load()
	local RelayCheck: any = loaded.require(loaded.game:GetService("ServerScriptService").Server.RelayCheck)

	-- 1) Two records alike find nothing
	local same: any = summary()
	RelayCheck.compare(LAYOUT, RUN, record(), record(), same)
	if same.found ~= 0 then
		return false, `Two matching records gave {same.found} mismatches: {table.concat(same.mismatches, " | ")}`
	end

	-- 2) One byte of one block planted apart, named with its layout, run, recipient and first differing byte
	local workers: any = record()
	workers.blocks.fight2[2] = PLANTED

	local planted: any = summary()
	RelayCheck.compare(LAYOUT, RUN, record(), workers, planted)
	if planted.found ~= 1 or planted.mismatches[1] ~= MATCHED then
		return false, `A block one byte apart gave {planted.found}: {table.concat(planted.mismatches, " | ")}`
	end

	-- 3) A withheld block missing and a query apart, each named
	local short: any = record()
	short.withheld.Moderator = {}
	short.queries.counts = "12 5 30"

	local both: any = summary()
	RelayCheck.compare(LAYOUT, RUN, record(), short, both)
	if both.found ~= 2 or both.mismatches[1] ~= MISSING or both.mismatches[2] ~= QUERY then
		return false, `A missing block and a query apart gave {both.found}: {table.concat(both.mismatches, " | ")}`
	end

	return true, nil
end
