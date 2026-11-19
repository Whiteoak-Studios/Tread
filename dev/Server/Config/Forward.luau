--[[
    The report forward's own settings: the rate at which each player is
    sent the reports Tread raised about them
--]]

--!strict
return {
	-- Room for a cheat's steady flood, a stand-in every tick and a report each Move beside it, and a lag switch's release
	rate = { perSecond = 40, burst = 80 },
}
