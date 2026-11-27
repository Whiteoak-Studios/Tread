--[[
    The bot panel's numbers on the dev server: the most bots it holds, how
    it looks for ground under each and waits for their views, how often it
    sends the server's numbers, the split's attribute, and each ask's rate
--]]

--!strict
return {
	-- Panel bots at once at most, G10's 300 players beside the one real client. A Volt bot takes no server slot, and
	-- these with the real players stay far inside Tread's 4,096 character slots
	cap = 299,

	tries = 8, -- Points drawn for a bot before it is left unbuilt, when none of them is over ground
	interval = 1, -- Seconds of Heartbeats each send of the server's numbers covers
	median = 0.5, -- The share the frame times and the tick stages' totals show their middle at
	high = 0.95, -- And their high end, which each stage's time shows at too
	reasonBytes = 200, -- Bytes a refusal carries at most, the botRefused event's own bound in Dev.volt

	-- Heartbeats a spawn on a server with relay workers waits at most, after its last bot, for the relay run that makes
	-- their views on the workers, about 2 s at 60 a second where a run comes every 3
	homeBeats = 120,

	-- The Workspace attribute the relay's split by stage is kept in, which the dev server's settings read at boot
	splitAttribute = "TreadRelaySplit",

	rates = {
		spawn = { perSecond = 1, burst = 2 }, -- Spawn asks a second, where a click on the panel sends one
		clear = { perSecond = 1, burst = 2 },
		watch = { perSecond = 4, burst = 8 }, -- Shows and hides a second, where each press of the panel's key sends one
		split = { perSecond = 1, burst = 2 }, -- Asks for the split on or off a second, where a click sends one
	},
}
