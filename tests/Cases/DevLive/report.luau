--[[
    A run's report leaves out the bot run's per-second lines and G8's
    per-episode lines and keeps the rest in order, and past its size keeps
    the head, then how much it cut, then the newest line, the verdict
--]]

--!strict
local Harness = require("../../Fixtures/DevServer/Harness")

local LINE_BYTES: number = 99 -- Each filler line's, 100 with its newline, so the head holds a whole number of them
local PAST: number = 80 -- Filler lines past what the head holds
local RUN: string = "LateReveals"
local VERDICT: string = `Runner PASS {RUN}: passed`

-- An episode as G8's probe finds one, under each set and reading
local EPISODES: { { [string]: any } } = {
	{
		set = "body",
		reading = "lenient",
		viewer = "Bot1",
		target = "Bot2",
		real = false,
		distance = 12.5,
		point = 1,
		height = 1.8,
		speed = 14,
		start = 100,
		length = 3,
		reason = "Visible",
		hullOnly = false,
	},
	{
		set = "hull",
		reading = "strict",
		viewer = "Player1",
		target = "Bot7",
		real = true,
		distance = 40,
		point = 4,
		height = 2.7,
		speed = 0,
		start = 2001,
		length = 1,
		reason = "Hidden",
		hullOnly = true,
	},
}

-- A filler line of exactly LINE_BYTES, numbered so each differs
local function filler(index: number): string
	local number: string = string.format("filler %04d ", index)
	return `{number}{string.rep("x", LINE_BYTES - #number)}`
end

return function (): (boolean, string | nil)
	local loaded: Harness.Loaded = Harness.load()
	local server: any = loaded.game:GetService("ServerScriptService").Server
	local shared: any = loaded.game:GetService("ReplicatedStorage").Shared
	local LiveRuns: any = loaded.require(shared.Dev.LiveRuns)
	local Reveals: any = loaded.require(server.Reveals)
	local config: any = loaded.require(server.Config.Live)

	local episodeLines: { string } = {}
	for _, episode: { [string]: any } in EPISODES do
		table.insert(episodeLines, Reveals.describe(episode))
	end

	local kept: { string } = {
		"Bots S3 seed 2: starting, its areas moved (0, 0, 0), with 1 real players in",
		"Bots S3 seed 2 group city: 60 bots",
		Reveals.byPoint(EPISODES),
		"Bots S3 seed 2 probe: G8: 8 viewers (1 real) over 0.40 viewer-hours",
		"Warning: Bots S3 seed 2 second 4: a warning that looks like a per-second line",
		"G8 body lenient late reveals: 3, which is no episode's line",
		VERDICT,
	}

	local arriving: { string } = {
		kept[1],
		"Bots S3 seed 2 second 1: real players 1, viewers {}, stats {}",
		kept[2],
		"Bots S3 seed 2 second 120: real players 1, viewers {}, stats {}",
		episodeLines[1],
		kept[3],
		episodeLines[2],
		kept[4],
		kept[5],
		kept[6],
		kept[7],
	}

	-- 1) Under the size, the per-second and per-episode lines left out and the rest kept in order
	local report: any = LiveRuns.report(RUN, config.reportBytes, config.dropped)
	for _, line: string in arriving do
		LiveRuns.collect(report, line)
	end

	local text: string = LiveRuns.text(report)
	if text ~= table.concat(kept, "\n") then
		return false, `The report under its size read:\n{text}`
	end

	-- 2) Past the size, the head, then the cut lines' count and bytes, then the verdict last
	local held: number = config.reportBytes // (LINE_BYTES + 1)
	local full: any = LiveRuns.report(RUN, config.reportBytes, config.dropped)
	for index: number = 1, held + PAST do
		LiveRuns.collect(full, filler(index))

		-- A dropped line past the size is still left out, never counted as cut
		LiveRuns.collect(full, `Bots S0 seed 1 second {index}: real players 1`)
	end

	LiveRuns.collect(full, VERDICT)

	local lines: { string } = string.split(LiveRuns.text(full), "\n")
	local notice: string = `... {PAST} lines ({PAST * LINE_BYTES} B) cut`
	if #lines ~= held + 2 then
		return false, `The full report held {#lines} lines, not its head of {held}, the notice and the verdict`
	elseif lines[1] ~= filler(1) or lines[held] ~= filler(held) then
		return false, "The full report's head was not its first lines in order"
	elseif lines[held + 1] ~= notice then
		return false, `The full report's notice read {lines[held + 1]}, not {notice}`
	elseif lines[held + 2] ~= VERDICT then
		return false, `The full report ended with {lines[held + 2]}, not the verdict`
	end

	-- 3) One line past the size is shown with no notice, since nothing was cut
	local barely: any = LiveRuns.report(RUN, config.reportBytes, config.dropped)
	for index: number = 1, held do
		LiveRuns.collect(barely, filler(index))
	end

	LiveRuns.collect(barely, VERDICT)
	local barelyLines: { string } = string.split(LiveRuns.text(barely), "\n")
	if #barelyLines ~= held + 1 or barelyLines[held + 1] ~= VERDICT then
		return false, "A report one line past its size did not end with that line alone"
	end

	return true, nil
end
