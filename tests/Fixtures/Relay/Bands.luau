--[[
    The dev place's three distance bands and their edges, built fresh on
    every call, for the relay cases that run three bands in place of the
    example's two
--]]

--!strict
local Bands = {}

-- 20 Hz with a 15 Hz floor, then 10 and 5 Hz, each with its floor at its aim, nearest first
function Bands.bands(): { { aim: number, floor: number } }
	return { { aim = 20, floor = 15 }, { aim = 10, floor = 10 }, { aim = 5, floor = 5 } }
end

-- In at 350 studs and out at 385, then in at 600 and out at 660
function Bands.edges(): { { enter: number, leave: number } }
	return { { enter = 350, leave = 385 }, { enter = 600, leave = 660 } }
end

-- Gives a server table the three bands, as a harness's tweak takes it
function Bands.three(_: any, server: any)
	server.tiers.bands = Bands.bands()
	server.tiers.edges = Bands.edges()
end

return Bands
