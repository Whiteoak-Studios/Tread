--[[
    The correction telemetry's own settings: the rate a client may report
    its replays at, and the size past which G2 counts a replay as large
--]]

--!strict
return {
	-- A client replays at most once an OwnerState, 20 a second at the relay rate, so an honest one is never refused
	rate = { perSecond = 20, burst = 40 },

	small = 0.1, -- Studs: a replay this far or less with no flag flipped is small, and any other is large
}
