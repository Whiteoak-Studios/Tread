--[[
    The ghosts' numbers on the dev server: the rate a viewer's asks take,
    and the most bytes the label of each send carries
--]]

--!strict
return {
	-- Asks a second, where a client resends its ask only when the set it draws changes, at most every 0.25 s
	rate = { perSecond = 4, burst = 8 },

	labelBytes = 32, -- Bytes the label carries at most, the ghosts event's own bound in Dev.volt
}
