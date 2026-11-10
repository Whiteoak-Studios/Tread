--[[
    G8's late-reveal numbers: the viewers observed, the exact test's inset
    and grace, the G8 load's timings, and the doorway and window check's
    folders, batches, waits and where it stands each pair
--]]

--!strict
return {
	viewers = 8, -- Bots observed beside every real player, the first of their group by build order
	group = "city", -- The group of the G8 load they come from
	inset = 0.05, -- Studs each of the hull's points is pulled inside it, so a ray to a corner ends in the hull
	grace = 1, -- Relay intervals a target may stay visible and unsent before a late reveal counts

	-- The G8 load's runs, through the bot harness
	full = { seeds = { 1, 2, 3 }, warmup = 30, window = 600, interval = 1 },
	smoke = { seeds = { 1 }, warmup = 5, window = 20, interval = 1 },

	openings = {
		folders = { { "TestContent", "CityBlock", "Markers" } }, -- Each a path under Workspace holding marker parts
		batch = 20, -- Pairs stood at once
		settle = 1, -- Seconds a batch settles before it is watched
		hold = 2, -- Seconds it is watched
		probe = 8, -- Studs cast both ways along each horizontal axis from a marker, its opening's axis the roomier
		view = 12, -- Studs out the viewer stands at most
		margin = 1, -- Studs the viewer's hull keeps clear of what its side's cast meets
		inside = 1.5, -- Studs past its hull's radius the target stands in from the marker
		platform = Vector3.new(3, 1, 3), -- What each bot stands on, laid outside anti-ESP's include list
		lift = 0.5, -- Studs above its platform each bot is built at, so it settles onto it
		smoke = 6, -- Markers the smoke run takes
	},
}
