--[[
    The bot harness counts each relay round once, in by the next Heartbeat
    or later, whether it went out in the tick's own Heartbeat or in a
    deferred tick's rest, with the split off, on, and turned on in a window
--]]

--!strict
local Harness = require("../../Fixtures/DevServer/Harness")
local Kit = require("../../Fixtures/Exploits/Kit")

local RUN: string = "dev/Server/Bots/Run.luau"

-- One window's Heartbeat flags, what it shows, and the rounds in by the next Heartbeat and later it counts
type Row = { name: string, flags: { number }, inTime: number, late: number }

return function (): (boolean, string | nil)
	local loaded: Harness.Loaded = Harness.load()
	local dataModel: any = loaded.game
	local server: any = dataModel:GetService("ServerScriptService").Server
	local Tick: any = loaded.require(dataModel:GetService("ReplicatedStorage").Packages.Tread.Server.Tick)

	-- Stand-ins for the dev game and its fleet, whose real modules start the dev game's server when required
	local results: { [any]: any } = { [server.Game] = {}, [server.Bots.Fleet] = {} }
	local Run: any = Kit.loader(dataModel, { [server.Bots.Run] = RUN }, results, loaded.require)(server.Bots.Run)

	local ticked: number, held: number, polled: number = Tick.TICKED, Tick.HELD, Tick.POLLED
	local released: number, deferred: number = Tick.RELEASED, Tick.DEFERRED

	local rows: { Row } = {
		{
			-- The split off, as heartbeatPlaces has it: a round out and its release, three with none, a serial tick, a
			-- round out, still held, its release, two with none
			name = "the split off",
			flags = {
				0,
				ticked + held,
				polled + released,
				0,
				0,
				0,
				ticked,
				ticked + held,
				polled + held,
				polled + released,
				0,
				0,
			},
			inTime = 1,
			late = 1,
		},
		{
			-- A calm deferral: the tick alone, its rest dispatching and held, the poll releasing it
			name = "a calm deferral in time",
			flags = { ticked, deferred + held, polled + released, 0 },
			inTime = 1,
			late = 0,
		},
		{
			-- Its round still out at the next Heartbeat's poll, released at the one after
			name = "a deferral released late",
			flags = { ticked, deferred + held, polled + held, polled + released, 0 },
			inTime = 0,
			late = 1,
		},
		{
			-- A tick owed on the rest's Heartbeat skips the rest, runs whole and holds its own round, the only one
			name = "a skipped rest",
			flags = { ticked, deferred + ticked + held, polled + released, 0 },
			inTime = 1,
			late = 0,
		},
		{
			-- A rest whose round was released inside its own stage holds nothing, so no round is counted
			name = "a rest released inside its stage",
			flags = { ticked, deferred + released, 0 },
			inTime = 0,
			late = 0,
		},
		{
			-- A release that runs the next tick, which holds a round of its own, on the split off
			name = "a release that dispatches",
			flags = { ticked + held, polled + released + ticked + held, polled + released },
			inTime = 2,
			late = 0,
		},
		{
			-- The split turned on inside the window: a round in time and one late on the tick's own Heartbeat, then a
			-- deferral in time and one late on the rest's
			name = "the split turned on in the window",
			flags = {
				ticked + held,
				polled + released,
				ticked + held,
				polled + held,
				polled + released,
				ticked,
				deferred + held,
				polled + released,
				ticked,
				deferred + held,
				polled + held,
				polled + released,
				0,
			},
			inTime = 2,
			late = 2,
		},
		{
			-- The newest Heartbeat has none after it, so its round counts as neither
			name = "a deferral at the window's end",
			flags = { ticked, deferred + held },
			inTime = 0,
			late = 0,
		},
	}

	for _, row: Row in rows do
		local inTime: number, late: number = Run.rounds(row.flags)
		if inTime ~= row.inTime or late ~= row.late then
			local wanted: string = `{row.inTime} and {row.late}`
			return false,
				`With {row.name}, the rounds read {inTime} in by the next Heartbeat and {late} later, not {wanted}`
		end
	end

	return true, nil
end
