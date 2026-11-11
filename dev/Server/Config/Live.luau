--[[
    The live runs' numbers on the dev server: the rate a run is asked for,
    the report's size, its wait for the verdict line and its pieces, and
    the lines it leaves out
--]]

--!strict
return {
	rate = { perSecond = 1, burst = 2 }, -- Run asks a second, where a click on the panel sends one

	pieceBytes = 4000, -- Bytes each piece of a report carries at most, the runReport event's own bound in Dev.volt
	reportBytes = 32000, -- Bytes of a run's Output the report keeps, past which it gives the count cut and the verdict
	verdictWait = 5, -- Seconds after a run returns the report waits for the Runner's verdict line to reach it

	-- The bot run's per-second lines and G8's per-episode lines, too many to paste
	dropped = { "^Bots %S+ seed %d+ second %d+: ", "^G8 %a+ %a+ late reveal: " },
}
