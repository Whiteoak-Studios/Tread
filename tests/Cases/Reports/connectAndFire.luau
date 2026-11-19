--[[
    A report reaches every callback in the order they connected, with its
    player or bot, kind and measurement, for every kind Tread reports
--]]

--!strict
local roblox: any = require("@lune/roblox")

local Environment = require("../../Environment")

local REPORTS: string = "src/Server/Reports.luau"
local COMMAND: number = 41 -- A moveTamper's measurement, the command number
local DETAIL: string = "Volt's detail"
local STAGE: string = "zones"

-- Every kind game-integration.md lists: Tread's own, then Volt's failures on Tread's scope
local KINDS: { string } = {
	"moveTamper",
	"schema",
	"rate",
	"gap",
	"late",
	"standIn",
	"lateShot",
	"ahead",
	"band",
	"snapBack",
	"stuck",
	"sleep",
	"stage",
	"packet",
	"handshake",
	"listener",
	"handler",
	"outgoing",
	"queue",
	"departed",
}

type Heard = { player: any, kind: string, measurement: number | string }

return function (): (boolean, string | nil)
	local Reports = Environment.load(REPORTS)
	local order: { string } = {}
	local heard: { Heard } = {}

	Reports.connect(function (player: any, kind: string, measurement: number | string)
		table.insert(order, "first")
		table.insert(heard, { player = player, kind = kind, measurement = measurement })
	end)

	Reports.connect(function ()
		table.insert(order, "second")
	end)

	local player: any = roblox.Instance.new("Player")
	local bot: { Name: string } = { Name = "Bot" }

	Reports.fire(player, "moveTamper", COMMAND)
	Reports.fire(bot, "schema", DETAIL)
	Reports.fire(nil, "stage", STAGE)

	local sequence: string = table.concat(order, " ")
	if sequence ~= "first second first second first second" then
		return false, `The callbacks ran as {sequence}, not first then second for each report`
	end

	local first: Heard, second: Heard, third: Heard = heard[1], heard[2], heard[3]
	if first.player ~= player or first.kind ~= "moveTamper" or first.measurement ~= COMMAND then
		return false, "A player's report reached its callback changed"
	elseif second.player ~= bot or second.kind ~= "schema" or second.measurement ~= DETAIL then
		return false, "A bot's report reached its callback changed"
	elseif third.player ~= nil or third.kind ~= "stage" or third.measurement ~= STAGE then
		return false, "A report about no player reached its callback changed"
	end

	for _, kind: string in KINDS do
		local fired: boolean, problem: any = pcall(Reports.fire, nil, kind, COMMAND)
		if not fired then
			return false, `Reports.fire refused the kind {kind}: {problem}`
		end
	end

	if #heard ~= 3 + #KINDS then
		return false, `{#heard} reports reached the first callback, not {3 + #KINDS}`
	end

	return true, nil
end
