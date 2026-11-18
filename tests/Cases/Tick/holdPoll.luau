--[[
    A hold with a poll runs it first each Heartbeat while held, nothing else,
    and ends once it answers true or throws, its time in the finishes with
    the tick held; the release runs the rest as Tick.release does
--]]

--!strict
local Environment = require("../../Environment")
local Frames = require("../../Fixtures/Server/Frames")

local GLOBALS: string = "tests/Fixtures/Environment/Globals.luau"
local RATE: number = 20
local CATCH_UP: number = 2
local HALF: number = 0.5 -- A tick's share past a frame's whole ticks, so none lands on a tick's edge
local QUARTER: number = 0.25 -- A smaller share, which with a half left over still owes no tick

return function (): (boolean, string | nil)
	local globals: any = Environment.load(GLOBALS)
	local frames: Frames.Frames = Frames.new(globals)
	local tread: any = globals.game:GetService("ReplicatedStorage").Packages.Tread
	local Reports: any = globals.require(tread.Server.Reports)
	local Tick: any = globals.require(tread.Server.Tick)

	local order: { string } = {}
	local holds: { [number]: string } = {} -- How the holder holds on each tick it names
	local answer: boolean = false -- What every poll answers, unless throwing
	local throwing: boolean = false
	local refusal: any = nil
	local reports: { string } = {}

	Reports.connect(function (player: any, kind: string, measurement: any)
		table.insert(reports, `{kind} {measurement} {player}`)
	end)

	-- The stages run since the last call, which it clears, and the counts
	local function taken(): string
		local ran: number, dropped: number = Tick.counts()
		local got: string = `{table.concat(order, ", ")}; ran {ran}, dropped {dropped}`
		table.clear(order)

		return got
	end

	local function stage(name: string, between: boolean): { name: string, between: boolean, run: (tick: number) -> () }
		return {
			name = name,
			between = between,
			run = function (tick: number)
				table.insert(order, `{name} {tick}`)

				local how: string? = holds[tick]
				if name ~= "holder" or how == nil then
					return
				elseif how == "badPoll" then
					local held: boolean, message: any = pcall(Tick.hold, "a poll")
					refusal = not held and message

					return
				end

				Tick.hold(function (): boolean
					table.insert(order, `poll {tick}`)
					if throwing then
						error("This poll throws on purpose, to show the hold still ends")
					end

					return answer
				end)
			end,
		}
	end

	Tick.start(RATE, CATCH_UP, {
		stage("before", false),
		stage("slices", true),
		stage("holder", false),
		stage("after", false),
	})

	-- The hold's own frame never polls, and each held frame after it polls first and runs nothing else
	holds[1] = "poll"
	frames:run((1 + QUARTER) / RATE)

	local got: string = taken()
	if got ~= "before 1, slices 1, holder 1; ran 1, dropped 0" then
		return false, `The frame whose tick held with a poll ran {got}`
	end

	frames:run(1 / RATE)
	frames:run(1 / RATE)

	got = taken()
	if got ~= "poll 1, poll 1; ran 1, dropped 0" then
		return false, `Two held frames whose poll answered false ran {got}`
	elseif Tick.finishes().held ~= 0 then
		return false, "A poll that answered false was kept in the finishes"
	end

	-- A true answer ends the hold first thing, three ticks owed: the held tick's rest, one between pass, the catch-up,
	-- the rest dropped
	answer = true
	frames:run(1 / RATE)

	got = taken()
	local expected: string =
		"poll 1, after 1, before 2, slices 2, holder 2, after 2, before 3, holder 3, after 3; ran 3, dropped 1"
	if got ~= expected then
		return false, `The frame whose poll answered true ran {got}`
	end

	-- Ended with no tick owed, the between stages run alone after the held tick's rest
	holds[4] = "poll"
	frames:run(1 / RATE)
	taken()
	frames:run(HALF / RATE)

	got = taken()
	if got ~= "poll 4, after 4, slices 4; ran 4, dropped 1" then
		return false, `A poll that answered true with no tick owed ran {got}`
	end

	-- A poll that throws is reported as the holding stage's and still ends the hold
	holds[5] = "poll"
	frames:run(HALF / RATE)
	taken()
	throwing = true
	frames:run(1 / RATE)
	throwing = false

	got = taken()
	if got ~= "poll 5, after 5, before 6, slices 6, holder 6, after 6; ran 6, dropped 1" then
		return false, `The frame whose poll threw ran {got}`
	elseif #reports ~= 1 or reports[1] ~= "stage holder nil" then
		return false, `The poll that threw gave the reports {table.concat(reports, ", ")}, not stage holder`
	end

	-- A tick the release runs may hold again, and its own poll ends that hold at the next frame
	holds[7] = "poll"
	holds[8] = "poll"
	frames:run((CATCH_UP + QUARTER) / RATE)
	taken()
	frames:run(QUARTER / RATE)

	got = taken()
	if got ~= "poll 7, after 7, before 8, slices 8, holder 8; ran 8, dropped 1" then
		return false, `A release whose next tick held again ran {got}`
	end

	frames:run(HALF / RATE)

	got = taken()
	if got ~= "poll 8, after 8, before 9, slices 9, holder 9, after 9; ran 9, dropped 1" then
		return false, `The second hold's poll ran {got}`
	end

	-- Each hold a poll ended is in the finishes in turn, with the tick it held
	local finishes: any = Tick.finishes()
	local held: { string } = {}
	for index: number = 1, finishes.held do
		table.insert(held, `{finishes.ticks[index]}`)
		if not (finishes.times[index] >= 0) then
			return false, `The finishes' time {index} is {finishes.times[index]}`
		end
	end

	if table.concat(held, ",") ~= "1,4,5,7,8" or finishes.last ~= finishes.times[finishes.held] then
		return false, `The finishes held ticks {table.concat(held, ",")}, not 1,4,5,7,8 with the newest last`
	end

	-- Tick.release from outside ends a hold with a poll, which is never tried again
	holds[10] = "poll"
	answer = false
	frames:run(1 / RATE)
	taken()
	Tick.release()
	frames:run(QUARTER / RATE)

	got = taken()
	if got ~= "after 10, slices 10; ran 10, dropped 1" then
		return false, `Tick.release on a hold with a poll and the frame after ran {got}`
	elseif Tick.finishes().held ~= 5 then
		return false, "A hold Tick.release ended was kept in the finishes"
	end

	-- A poll that is no function is refused naming its call, and leaves the tick unheld
	holds[11] = "badPoll"
	frames:run((1 - QUARTER) / RATE)

	got = taken()
	if got ~= "before 11, slices 11, holder 11, after 11; ran 11, dropped 1" then
		return false, `A tick whose hold took no function ran {got}`
	elseif not string.find(tostring(refusal), "Tick.hold", 1, true) then
		return false, `A hold given a string as its poll was not refused naming its call: {refusal}`
	end

	return true, nil
end
