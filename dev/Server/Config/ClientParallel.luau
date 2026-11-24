--[[
    The client parallel probes' run on the dev server: the attribute each
    probe's window opens on, the reports' rate and wait, and the run of G5's
    load each window sits beside
--]]

--!strict
return {
	attributes = {
		cores = "ClientCores", -- P6's window's, the one the dev client's probe watches for it
		bend = "ClientBend", -- P8's
	},

	rate = { perSecond = 1, burst = 2 }, -- clientCost reports a second, where a client sends one a window
	wait = 5, -- Seconds after a window ends the server waits for each real player's report

	-- One short seed of G5's load beside each probe, its window long enough for every arm its probe runs
	timing = { seeds = { 1 }, warmup = 10, window = 60, interval = 1 },
}
