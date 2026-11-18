--[[
    Each Heartbeat goes into the per-Heartbeat ring with all the loop's work
    in it timed and what it did flagged, a tick, a hold, a poll, a release
    with owed ticks and none, and each ring entry carries its Heartbeat
--]]

--!strict
local Environment = require("../../Environment")
local Frames = require("../../Fixtures/Server/Frames")

local GLOBALS: string = "tests/Fixtures/Environment/Globals.luau"
local RATE: number = 20
local CATCH_UP: number = 2
local SPIN: number = 0.005 -- Seconds a busy stage or poll holds the loop, which its Heartbeat's time must take in

-- Each frame's ticks owed, none landing on a tick's edge: a tick; none; a tick that holds; the hold polled false;
-- the poll true with two ticks owed; none
local OWED: { number } = { 1.5, 0.25, 0.5, 1, 1, 0.25 }
local HOLDS: number = 2 -- The tick the holder holds
local POLL_FALSE: number = 4 -- The frame whose poll answers false
local SPINS: { [number]: boolean } = { [1] = true, [2] = true, [3] = true } -- The ticks the busy stage spins on

-- Each frame's flags, as a sum of Tick's: ticked 1, held 2, polled 4, released 8
local FLAGS: { number } = { 1, 0, 3, 6, 13, 0 }
local SPUN: { number } = { 1, 3, 4, 5 } -- The frames whose time takes in a spin: the ticks 1 to 3 and the false poll

-- The Heartbeat each stage's runs came in, tick by tick: the held tick's rest at the release's frame
local BEATS: { [string]: string } = { busy = "1,3,5,5", after = "1,5,5,5", slices = "1,2,3,5,6" }

-- Holds the loop for SPIN seconds
local function spin()
	local ends: number = os.clock() + SPIN
	while os.clock() < ends do
		continue
	end
end

return function (): (boolean, string | nil)
	local globals: any = Environment.load(GLOBALS)
	local frames: Frames.Frames = Frames.new(globals)
	local Tick: any = globals.require(globals.game:GetService("ReplicatedStorage").Packages.Tread.Server.Tick)

	local frame: number = 0
	local holding: { boolean } = {}

	Tick.start(RATE, CATCH_UP, {
		{
			name = "busy",
			run = function (tick: number)
				if SPINS[tick] then
					spin()
				end
			end,
		},
		{ name = "slices", between = true, run = function (_: number) end },
		{
			name = "holder",
			run = function (tick: number)
				if tick == HOLDS then
					Tick.hold(function (): boolean
						if frame == POLL_FALSE then
							spin()
							return false
						end

						return true
					end)
				end
			end,
		},
		{ name = "after", run = function (_: number) end },
	})

	for index: number, owed: number in OWED do
		frame = index
		frames:run(owed / RATE)
		holding[index] = Tick.holding()
	end

	-- 1) Every frame in the ring, flagged with what the loop did in it, oldest first from the ring's start
	local beats: any = Tick.heartbeats()
	if beats.count ~= #OWED or beats.held ~= #OWED or beats.head ~= #OWED then
		return false, `After {#OWED} frames the ring counts {beats.count}, holds {beats.held} at head {beats.head}`
	end

	local flags: string = table.concat(table.move(beats.flags, 1, #OWED, 1, {}), ",")
	if flags ~= table.concat(FLAGS, ",") then
		return false, `The frames were flagged {flags}, not {table.concat(FLAGS, ",")}`
	elseif not (holding[3] and holding[4] and not holding[5]) then
		return false, "Tick.holding did not answer true from the hold's frame until its release"
	end

	-- 2) Every frame's time by os.clock(), each one with a spin in it taking that spin in
	for index: number = 1, #OWED do
		if not (beats.times[index] >= 0) then
			return false, `Frame {index}'s time is {beats.times[index]}`
		end
	end

	for _, index: number in SPUN do
		if not (beats.times[index] >= SPIN) then
			return false, `Frame {index} spun {SPIN} s inside the loop and its time is {beats.times[index]}`
		end
	end

	-- 3) Each ring entry carries the frame it came in, the held tick's rest and the release's ticks the release's
	for _, stage: any in Tick.stages() do
		local expected: string? = BEATS[stage.name]
		local got: string = table.concat(table.move(stage.beats, 1, stage.held, 1, {}), ",")
		if expected and got ~= expected then
			return false, `The {stage.name} stage's runs came in the frames {got}, not {expected}`
		end
	end

	local finishes: any = Tick.finishes()
	if finishes.held ~= 1 or finishes.beats[1] ~= 5 or finishes.ticks[1] ~= HOLDS then
		return false, `The finish of tick {finishes.ticks[1]} came in frame {finishes.beats[1]}, not tick {HOLDS} in 5`
	end

	return true, nil
end
