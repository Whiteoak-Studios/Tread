--[[
    The versus run on the dev server: the attribute each window opens with,
    and the rate of and the wait for each real player's receive line
--]]

--!strict
return {
	attribute = "ClientReceive", -- The Workspace attribute set to a window's label, the one the dev client's receive watches
	rate = { perSecond = 1, burst = 2 }, -- clientCost reports a second, where a client sends one a window
	wait = 5, -- Seconds after a window ends the server waits for each real player's line
}
