--[[
    The frame figures' numbers, which both arms' client lines read: the
    shares their spreads and frame rate are read at, and the frame times
    past which a frame counts as a hitch
--]]

--!strict
return {
	-- The frame time's and the render times', and on ClientCost's line the remote work's, as each line prints them
	percentiles = { 0.5, 0.95, 0.99 },
	fps = 0.1, -- The share the frame rate is read at
	spike = 2, -- A frame longer than this many times the window's median frame counts as a hitch
	hitch = 33.3, -- Milliseconds past which a frame counts as a hitch whatever the median, under 30 frames a second
}
