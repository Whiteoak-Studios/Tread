--[[
    The run that sends every real player to a fresh reserved server of the
    A0 arm's place: where it sends them, and how many tries and waits each
    teleport gets
--]]

--!strict
return {
	placeId = 108848112043191, -- The A0 arm's place, in the dev place's universe, which a player reaches only by teleport
	attempts = 5, -- TeleportAsync tries before the run fails, as Roblox's teleport guide retries
	retryDelay = 1, -- Seconds before the next try after a failed one
	floodDelay = 15, -- Seconds before the next try after a Flooded one
	callWait = 30, -- Seconds a TeleportAsync call may take to answer before its try fails
	settle = 15, -- Seconds after a call is taken that the run waits for each player to leave or hear a failure
}
