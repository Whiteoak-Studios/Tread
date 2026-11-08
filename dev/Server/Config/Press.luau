--[[
    The test elevator's call button's own settings: the rate a client may
    send its press at
--]]

--!strict
return {
	-- One press a key going down, so a player mashing the key stays under it, and a press past it was never honest
	rate = { perSecond = 5, burst = 10 },
}
