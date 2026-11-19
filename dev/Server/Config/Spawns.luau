--[[
    Where the dev game builds a joining player's character: the grid of
    points it lays over the plaza's spawn area, and how long it lets the
    engine stream a point's surroundings in before it builds anyway
--]]

--!strict
return {
	columns = 10, -- Points along the area's X; with the rows, the 60 players the area is built for
	rows = 6, -- Points along its Z
	lift = 0.5, -- Studs above the plaza floor a character is built at, so it settles onto it
	streamTimeout = 5, -- Seconds
}
