--[[
    The RenderDistance scenario's numbers: where it lays its floor, how far
    its two targets stand from the viewer, the render distances the viewer
    sends, and how long each of its waits may take
--]]

--!strict
return {
	center = Vector3.new(2000, 900, 2000), -- The floor's top, clear of the city block and every other scenario's floor
	floor = Vector3.new(660, 2, 40), -- Long along X, so the viewer and both targets stand on it with room at the ends
	lift = 0.5, -- Studs above the floor each bot is built at, so it settles onto it
	near = 300, -- Studs along X from the viewer to the nearer target
	far = 600,
	view = 400, -- The render distance the viewer's client sends first, between the two targets
	whole = 1000, -- The one it sends after, the dev server's relevancy.leave, which takes both in
	hold = 5, -- Relay frames the shorter view must keep the farther target unsent for
	wait = 10, -- Seconds each wait may take before the run fails
}
