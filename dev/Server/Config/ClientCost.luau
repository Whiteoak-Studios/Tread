--[[
    G5's client cost run on the dev server: the attribute each window opens
    with, the reports' rate and wait, and where the real players are set down
--]]

--!strict
return {
	attribute = "ClientCost", -- The Workspace attribute set to a window's label, the one the dev client's cost watches
	rate = { perSecond = 1, burst = 2 }, -- clientCost reports a second, where a client sends one a window
	wait = 5, -- Seconds after a window ends the server waits for each real player's report

	beside = 4, -- Studs along X from the first bot's feet the first real player is set down at, the nth n times as far
	lift = 0.5, -- Studs above that each real player is set down at, so the feet land on the ground
}
