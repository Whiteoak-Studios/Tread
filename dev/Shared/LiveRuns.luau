--[[
    The dev place's live runs: the scenarios its panel starts and the queue
    Run all takes, why the server refuses one, a run's report and its pieces
    over the dev scope, and what the panel shows of each
--]]

--!strict
local IDLE: string = "Idle" -- The panel's status before any run
local KEPT: string = "^Kept (%d+)$" -- An ask for a report the queue kept, by its place, 0 for the queue's state
local NEWLINE: string = "\n" -- Between the report's lines
local NEWLINE_BYTES: number = 1 -- What each line's newline adds to the report's head
local CHARACTER_BYTES: number = 4 -- The most bytes one UTF-8 character takes
local CONTINUATION_LOW: number = 0x80 -- A UTF-8 character's bytes after its first lie from here
local CONTINUATION_HIGH: number = 0xBF -- To here

-- A scenario the panel starts, by its module under dev/Server/Scenarios, and about how long it runs
export type Run = {
	name: string,
	minutes: number,
}

-- What the dev scope's runReport says of a run, the Run all queue's state, its kept reports' list, or one of them
export type State = "Refused" | "Running" | "Piece" | "Passed" | "Failed" | "Queue" | "Kept" | "Report"

-- What the panel shows: its status line, the queue's own while one has run, and the report so far
export type Panel = {
	status: string,
	queue: string, -- Empty before any queue
	text: string,
}

-- A run's Output as it arrives: the head kept up to the limit, then the lines past it counted and the newest kept
export type Report = {
	name: string, -- The run's
	limit: number, -- Bytes the head holds at most, each line's newline counted
	dropped: { string }, -- Patterns of the lines left out as they arrive
	head: { string },
	bytes: number, -- What the head holds
	full: boolean, -- Whether a line has passed the limit, after which the head takes no more
	cut: number, -- Lines past the limit, the newest not among them
	cutBytes: number,
	newest: string?, -- The newest line past the limit, the Runner's verdict once the run ends
	verdicts: { string }, -- How the Runner's verdict line for the run begins, passed or failed
	heard: boolean, -- Whether that line has arrived
}

local LiveRuns = {
	-- In campaign order, each about as long as its configs make it
	runs = {
		{ name = "BotsSmoke", minutes = 1.5 }, -- S0 to S7 once each, a 2 s warm-up and a 3 s window, and their builds
		{ name = "GatesSmoke", minutes = 2 }, -- The gates' seven loads the same way, S9's 2,000 sleepers and G10's 331 bodies
		{ name = "HarnessesSmoke", minutes = 2 }, -- G7's four cases at 10 s each, G8's 25 s smoke load and six openings
		{ name = "BenchS0", minutes = 7.5 }, -- 3 seeds of a 30 s warm-up and a 120 s window, as each bench run
		{ name = "BenchS1", minutes = 7.5 },
		{ name = "BenchS2", minutes = 7.5 },
		{ name = "BenchS3", minutes = 7.5 },
		{ name = "BenchS4", minutes = 7.5 },
		{ name = "BenchS3Npcs", minutes = 7.5 },
		{ name = "BenchS4Npcs", minutes = 7.5 },
		{ name = "BenchS9", minutes = 7.5 },
		{ name = "BenchS10", minutes = 7.5 },
		{ name = "BenchG10", minutes = 7.5 },
		{ name = "BenchG10Rung2", minutes = 7.5 }, -- G10's load with every NPC idle
		{ name = "ClientCost", minutes = 7.5 },
		{ name = "ParallelProbe", minutes = 0.2 }, -- The loop timed serially, then 50 batches at each of 5 worker counts
		{ name = "ParallelReturn", minutes = 0.5 }, -- P1's 600 rounds a Heartbeat apart, P4's values, P5's 28 rows of 30
		{ name = "BenchS5", minutes = 7.5 },
		{ name = "BenchS6", minutes = 7.5 },
		{ name = "BenchS7", minutes = 7.5 },
		{ name = "BenchRelevancy", minutes = 8 }, -- S3 and S4 at 3 render distances, one seed of a 15 s warm-up and 60 s each
		{ name = "Openings", minutes = 1 }, -- The city block's markers 20 at a time, 3 s a batch
		{ name = "LateReveals", minutes = 31.5 }, -- 3 seeds of a 30 s warm-up and a 600 s window
		{ name = "Corrections", minutes = 0.1 }, -- Prints the counts kept since each player joined
		{ name = "HitAgreement", minutes = 8.4 }, -- A 3 s settle, then 4 cases of a 3 s warm-up, 120 s firing, 2 s drain
	} :: { Run },

	-- What Run all runs one after another on one server, each a listed run needing neither a player's hands nor a server
	-- booted another way, the probe's Actors last so they run nothing before it
	queue = {
		"BenchS0",
		"BenchS1",
		"BenchS2",
		"BenchS3",
		"BenchS4",
		"BenchS5",
		"BenchS6",
		"BenchS7",
		"BenchS3Npcs",
		"BenchS4Npcs",
		"BenchS9",
		"BenchS10",
		"BenchRelevancy",
		"BenchG10",
		"BenchG10Rung2",
		"LateReveals",
		"Openings",
		"ClientCost",
		"ParallelProbe",
	},

	ALL = "Run all", -- The ask that starts the queue, which no run is named
}

-- The listed run of that name, nil for one not listed
local function find(name: string): Run?
	for _, run: Run in LiveRuns.runs do
		if run.name == name then
			return run
		end
	end

	return nil
end

--[[
    Why the server refuses a player's ask to start a run, nil when it
    doesn't: any ask while another run is going first, the queue's among
    them, then a name the list doesn't have, Run all aside
--]]

function LiveRuns.refusal(running: string?, name: string): string?
	if running then
		return `{running} is still running`
	elseif name ~= LiveRuns.ALL and not find(name) then
		return `no live run is named {name}`
	end

	return nil
end

-- The ask for the report the queue kept at that place, from 1, or with 0 for the queue's state and its list
function LiveRuns.kept(index: number): string
	return `Kept {index}`
end

-- The place an ask for a kept report names, nil for an ask that is none
function LiveRuns.keptIndex(name: string): number?
	local index: string? = string.match(name, KEPT)
	if index then
		return tonumber(index)
	end

	return nil
end

--[[
    The queue's status line: the run going, about how long it runs and how
    many follow it, or once the queue is done, how many it kept and failed
--]]

function LiveRuns.queueStatus(going: string?, left: number, kept: number, failed: number): string
	local tally: string = `{kept} kept, {failed} failed`
	if not going then
		return `Run all done: {tally}`
	end

	local run: Run? = find(going)
	local length: string = ""
	if run then
		length = `, about {run.minutes} min`
	end

	return `Run all: {going} running{length}, {left} left after it, {tally}`
end

--[[
    The report of the run of that name before any Output, which keeps at
    most limit bytes of lines and leaves out every line one of the dropped
    patterns matches
--]]

function LiveRuns.report(name: string, limit: number, dropped: { string }): Report
	return {
		name = name,
		limit = limit,
		dropped = dropped,
		head = {},
		bytes = 0,
		full = false,
		cut = 0,
		cutBytes = 0,
		newest = nil,

		-- As dev/Server/Runner.luau prints its verdict, whose report always begins with the run's name
		verdicts = { `Runner PASS {name}:`, `Runner FAIL {name}:` },
		heard = false,
	}
end

--[[
    Takes one line of Output as it arrives: marked heard when it is the
    Runner's verdict line for the run, left out when a dropped pattern
    matches it, kept in the head while the head has room, and past that
    counted as cut, but for the newest, which the text ends with
--]]

function LiveRuns.collect(report: Report, line: string)
	if not report.heard then
		for _, verdict: string in report.verdicts do
			if string.sub(line, 1, #verdict) == verdict then
				report.heard = true
			end
		end
	end

	for _, pattern: string in report.dropped do
		if string.find(line, pattern) then
			return
		end
	end

	local size: number = #line + NEWLINE_BYTES
	if not report.full and report.bytes + size <= report.limit then
		table.insert(report.head, line)
		report.bytes += size
		return
	end

	report.full = true

	local newest: string? = report.newest
	if newest then
		report.cut += 1
		report.cutBytes += #newest
	end

	report.newest = line
end

--[[
    Ends the report of a run whose verdict line never arrived with a line
    saying so, after the seconds the server waited for it, and leaves one
    that has its verdict line as it is
--]]

function LiveRuns.close(report: Report, seconds: number)
	if not report.heard then
		LiveRuns.collect(report, `No verdict line from the Runner for {report.name} arrived within {seconds} s`)
	end
end

--[[
    The report's text: the head, then, once the head is full, how many
    lines and bytes were cut and the newest line, a line each
--]]

function LiveRuns.text(report: Report): string
	local lines: { string } = table.clone(report.head)
	if report.cut > 0 then
		table.insert(lines, `... {report.cut} lines ({report.cutBytes} B) cut`)
	end

	local newest: string? = report.newest
	if newest then
		table.insert(lines, newest)
	end

	return table.concat(lines, NEWLINE)
end

--[[
    Cuts a text into pieces of at most size bytes that join back byte for
    byte, none for an empty text. A cut that would split a UTF-8 character
    backs off to its first byte. It errors on a size that is no whole
    number of at least one character's most bytes
--]]

function LiveRuns.split(text: string, size: number): { string }
	if not (size >= CHARACTER_BYTES) or size % 1 ~= 0 then
		error(`LiveRuns.split cuts pieces of a whole number of bytes from {CHARACTER_BYTES}, not {size}`, 2)
	end

	local pieces: { string } = {}
	local from: number = 1

	-- Each piece holds at least size less a character's bytes, so every pass moves on
	while from <= #text do
		local to: number = math.min(from + size - 1, #text)

		-- A character's bytes after its first are at most three, so a stray run of them in malformed text is cut where
		-- the backing off stops
		for _ = 1, CHARACTER_BYTES - 1 do
			local following: number? = string.byte(text, to + 1)
			if following == nil or following < CONTINUATION_LOW or following > CONTINUATION_HIGH then
				break
			end

			to -= 1
		end

		table.insert(pieces, string.sub(text, from, to))
		from = to + 1
	end

	return pieces
end

-- The panel before any run
function LiveRuns.idle(): Panel
	return { status = IDLE, queue = "", text = "" }
end

--[[
    What the panel shows once the server says a run's state. Running and a
    kept Report clear the report and Piece adds to it, while Passed, Failed
    and Refused set only the status, so a refused click never wipes a report
    not yet copied, and Queue sets the queue's line alone. The kept list is
    the panel's buttons, so it leaves what shows as it was
--]]

function LiveRuns.apply(panel: Panel, state: State, text: string): Panel
	local queue: string = panel.queue

	if state == "Running" then
		local run: Run? = find(text)
		local status: string = `Running {text}`
		if run then
			status = `Running {text}, about {run.minutes} min`
		end

		return { status = status, queue = queue, text = "" }
	elseif state == "Piece" then
		return { status = panel.status, queue = queue, text = `{panel.text}{text}` }
	elseif state == "Passed" then
		return { status = `Done: {text} passed`, queue = queue, text = panel.text }
	elseif state == "Failed" then
		return { status = `Failed: {text}`, queue = queue, text = panel.text }
	elseif state == "Queue" then
		return { status = panel.status, queue = text, text = panel.text }
	elseif state == "Report" then
		return { status = `Report {text}`, queue = queue, text = "" }
	elseif state == "Kept" then
		return { status = panel.status, queue = queue, text = panel.text }
	end

	return { status = `Refused: {text}`, queue = queue, text = panel.text }
end

return LiveRuns
