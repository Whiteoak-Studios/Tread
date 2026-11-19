--[[
    Replays a client reports over the dev scope count small up to the small
    limit with no flag flipped, and large past it or with a flag, from the
    start of counting, with the minutes they cover in a read of its own
--]]

--!strict
local Harness = require("../../Fixtures/DevServer/Harness")

local task = require("@lune/task")

local STEPS: number = 3 -- Mock steps a fire takes to reach the server, the handshake before it included
local PAST: number = 1e-3 -- Studs past the small limit a replay is large at
local WAIT: number = 0.05 -- Seconds between two reads, which the second's minutes must cover
local CHANGED: number = 99 -- A count written into a read, which must not reach the next read

return function (): (boolean, string | nil)
	local loaded: Harness.Loaded = Harness.load()
	local server: any = loaded.game:GetService("ServerScriptService").Server
	local shared: any = loaded.game:GetService("ReplicatedStorage").Shared

	local Corrections: any = loaded.require(server.Corrections)
	local small: number = loaded.require(server.Config.Corrections).small
	Corrections.start()

	local client: any = loaded.require(shared.Network.Client)
	local player: any = loaded.mock.players[1]
	Corrections.add(player)

	-- Small: none at all, and exactly the limit. Large: just past it, a flag at no size, and the most a float holds
	client.corrected.fire(0, false)
	client.corrected.fire(small, false)
	client.corrected.fire(small + PAST, false)
	client.corrected.fire(0, true)
	client.corrected.fire(math.huge, false)

	for _ = 1, STEPS do
		loaded.mock:step()
	end

	local counts: any = Corrections.get(player)
	if not counts then
		return false, "A player being counted read as nil"
	elseif counts.small ~= 2 or counts.large ~= 3 then
		return false, `Two small and three large replays counted {counts.small} small and {counts.large} large`
	elseif not (counts.minutes >= 0) then
		return false, `A read gave {counts.minutes} minutes`
	end

	task.wait(WAIT)

	counts.small = CHANGED
	local later: any = Corrections.get(player)
	if later.small ~= 2 then
		return false, `A count written into one read reached the next, which gave {later.small} small`
	elseif not (later.minutes > counts.minutes) then
		return false, `A read {WAIT} s later gave {later.minutes} minutes, no more than the first's {counts.minutes}`
	end

	return true, nil
end
