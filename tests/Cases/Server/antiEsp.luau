--[[
    Anti-ESP joins the tick between history and relay, a slice on every
    Heartbeat with no tick due too, its rays cast against the server's
    include list: a character behind a wall is not sent, a teammate is,
    and once the wall goes its recheck sends it; stats counts its tests
--]]

--!strict
local task = require("@lune/task")

local Rig = require("../../Fixtures/Server/Rig")

local ORDER: { string } = { "decode", "simulate", "npcs", "history", "antiEsp", "relay" }
local TICKS: number = 4
local SHARE: number = 0.5 -- A tick's share one short frame owes, so it runs no tick
local WALL_SIZE: vector = vector.create(1, 40, 40) -- Tall and wide enough to block every ray across it
local TEAM: number = 7
local RECHECKS: number = 2 -- Hidden rechecks' intervals waited, so the pair is due again whatever the timer's grain

return function (): (boolean, string | nil)
	local rig: Rig.Rig = Rig.new()
	local server: any = rig:start()
	local Relay: any = rig:require(rig.tread.Server.Relay)
	local Tick: any = rig:require(rig.tread.Server.Tick)

	if rig:occluders() ~= rig.settings.antiEsp.include then
		return false, "Anti-ESP's occlusion was not handed the server settings' include list"
	end

	local names: { string } = {}
	local stage: any = nil
	for _, entry: any in Tick.stages() do
		table.insert(names, entry.name)

		if entry.name == "antiEsp" then
			stage = entry
		end
	end

	if table.concat(names, ",") ~= table.concat(ORDER, ",") or not stage or not stage.between then
		return false, `The tick runs {table.concat(names, ", ")}, with antiEsp marked between {stage and stage.between}`
	end

	local removeWall: () -> () = rig:wall(vector.create(3, rig.floor + WALL_SIZE.y / 4, 0), WALL_SIZE)
	local viewer: any = rig.mock:addBot("Viewer")
	local seen: any = rig.mock:addBot("Seen")
	local watching: any = server:create(viewer, rig:at(0, 0))
	local target: any = server:create(seen, rig:at(6, 0))
	server:stats()

	-- A slice between ticks runs only anti-ESP's stage, which tests the pairs the relay first asked about
	rig:tick(1)
	local held: number = stage.held
	local ran: number = Tick.counts()
	rig.frames:run(SHARE / rig.rate)

	if stage.held ~= held + 1 or Tick.counts() ~= ran then
		return false, `A frame owing no tick ran anti-ESP {stage.held - held} times and {Tick.counts() - ran} ticks`
	end

	rig:tick(TICKS)

	if Relay.isSent(viewer, target._slot) then
		return false, "The character behind the wall was sent to the viewer"
	end

	local stats: any = server:stats()
	if not (stats.antiEspTests > 0) or not (stats.antiEspHidden > 0) or stats.antiEspFailOpens ~= 0 then
		local figures: string = `{stats.antiEspTests} tests, {stats.antiEspHidden} hidden`
		return false, `The read gave {figures} and {stats.antiEspFailOpens} fail-opens behind the wall`
	end

	local again: any = server:stats()
	if again.antiEspTests ~= 0 or again.antiEspHidden ~= 0 then
		return false, "A read straight after another gave anti-ESP tests above 0"
	end

	-- Teammates are always sent, wall or not
	watching:setTeam(TEAM)
	target:setTeam(TEAM)
	rig:tick(2)

	if not Relay.isSent(viewer, target._slot) then
		return false, "A teammate behind the wall was not sent"
	elseif pcall(target.setTeam, target, "red") then
		return false, "setTeam took a string"
	end

	watching:setTeam(nil)
	target:setTeam(nil)
	rig:tick(2)

	if Relay.isSent(viewer, target._slot) then
		return false, "With the teams cleared the character behind the wall was still sent"
	end

	-- Once the wall goes, the hidden pair's next recheck sends it
	removeWall()
	task.wait(RECHECKS / rig.settings.antiEsp.hiddenRate)
	rig:tick(2)

	if not Relay.isSent(viewer, target._slot) then
		return false, "With the wall gone the character was still not sent after its recheck"
	elseif server:stats().antiEspFailOpens ~= 0 then
		return false, "The pair was sent by failing open, not by its recheck"
	end

	return true, nil
end
