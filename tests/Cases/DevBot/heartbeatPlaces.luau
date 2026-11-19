--[[
    The bot harness takes each Heartbeat the tick loop's ring holds since its
    last read, across the wrap, with the bots' stage's time in it, counts the
    ones lost, places each in its tick and counts the relay's rounds
--]]

--!strict
local Harness = require("../../Fixtures/DevServer/Harness")
local Kit = require("../../Fixtures/Exploits/Kit")

local RUN: string = "dev/Server/Bots/Run.luau"
local SIZE: number = 12 -- The Heartbeats' ring, which holds Heartbeats 4 to 15 of the 15 run
local COUNT: number = 15
local THROUGH: number = 2 -- The newest Heartbeat the readout took before, so Heartbeat 3 is lost
local FIRST: number = 4 -- The oldest the ring holds

-- Each Heartbeat's flags from FIRST, as a sum of Tick's, ticked 1, held 2, polled 4 and released 8: none; a round out;
-- its release; three with none; a serial tick; a round out; still held; its release; two with none
local FLAGS: { number } = { 0, 3, 12, 0, 0, 0, 1, 3, 6, 12, 0, 0 }
local PLACES: string = "0,1,2,3,4,4,1,1,2,3,4,4"

-- The bots' stage's runs, the Heartbeat each came in and its time, in a full ring of 5 whose newest is at index 5: one
-- before the readout's last read, then one at the first release, one at the serial tick, and two at the second
-- release, the held tick's and an owed tick's
local BOT_BEATS: { number } = { 2, 6, 10, 13, 13 }
local BOT_TIMES: { number } = { 0.5, 0.25, 0.125, 0.0625, 0.03125 }
local BOTS: string = "0,0,0.25,0,0,0,0.125,0,0,0.09375,0,0"

return function (): (boolean, string | nil)
	local loaded: Harness.Loaded = Harness.load()
	local dataModel: any = loaded.game
	local server: any = dataModel:GetService("ServerScriptService").Server

	-- Stand-ins for the dev game and its fleet, whose real modules start the dev game's server when required
	local results: { [any]: any } = { [server.Game] = {}, [server.Bots.Fleet] = {} }
	local Run: any = Kit.loader(dataModel, { [server.Bots.Run] = RUN }, results, loaded.require)(server.Bots.Run)

	-- Heartbeat b went in at ring index (b - 1) % SIZE + 1, its time b ms
	local beats: any = {
		times = table.create(SIZE, 0),
		flags = table.create(SIZE, 0),
		held = SIZE,
		head = COUNT % SIZE,
		count = COUNT,
	}

	for beat: number = FIRST, COUNT do
		local index: number = (beat - 1) % SIZE + 1
		beats.times[index] = beat / 1000
		beats.flags[index] = FLAGS[beat - FIRST + 1]
	end

	local bots: any = {
		name = "bots",
		times = BOT_TIMES,
		ticks = table.create(#BOT_BEATS, 0),
		beats = BOT_BEATS,
		held = #BOT_BEATS,
		head = 0,
	}

	local readout: any = { times = {}, flags = {}, bots = {}, through = THROUGH, lost = 0 }
	Run.takeBeats(readout, beats, bots)

	-- 1) The Heartbeats the ring holds since the last read, oldest first, the one it no longer holds counted lost
	local flags: string = table.concat(readout.flags, ",")
	if flags ~= table.concat(FLAGS, ",") or readout.lost ~= 1 or readout.through ~= COUNT then
		return false, `The readout took the flags {flags}, lost {readout.lost} and stands at {readout.through}`
	end

	for index: number, time: number in readout.times do
		if time ~= (FIRST + index - 1) / 1000 then
			return false, `The readout's Heartbeat {index} took {time} s, not Heartbeat {FIRST + index - 1}'s`
		end
	end

	-- 2) The bots' stage's time in each, by the Heartbeat its run came in, none from before the last read
	local shares: string = table.concat(readout.bots, ",")
	if shares ~= BOTS then
		return false, `The bots' stage's time each Heartbeat read {shares}, not {BOTS}`
	end

	-- 3) A read with nothing new takes nothing and loses nothing
	Run.takeBeats(readout, beats, bots)
	if #readout.flags ~= #FLAGS or readout.lost ~= 1 then
		return false, `A read with no new Heartbeat left {#readout.flags} taken and {readout.lost} lost`
	end

	-- 4) Each one's place in its tick, 0 before the first tick and the last place for any past the third
	local places: string = table.concat(Run.places(readout.flags), ",")
	if places ~= PLACES then
		return false, `The Heartbeats were placed {places}, not {PLACES}`
	end

	-- 5) One round in by the next Heartbeat, one later
	local inTime: number, late: number = Run.rounds(readout.flags)
	if inTime ~= 1 or late ~= 1 then
		return false, `The rounds read {inTime} in by the next Heartbeat and {late} later, not 1 and 1`
	end

	return true, nil
end
