--[[
    While on, every Move the client sends is held from the server, and off
    lets them all go at once, oldest first, as they were sent; past the
    kit's limit the oldest held are dropped
--]]

--!strict
local Handle = require("../../Fixtures/Client/Handle")
local Kit = require("../../Fixtures/Exploits/Kit")

local OWN: number = 9
local TICK: number = 100
local HELD: number = 5 -- Relay ticks the switch holds, a Move each
local LIMIT: number = 2 -- The hold's limit in the second rig

-- A rig whose client sends a Move each frame, its lag switch started under a hold limit, if one is given
local function rigged(limit: number?): (any, (on: boolean) -> ())
	local rig: any = Handle.new()
	rig.handshake()
	rig.own(OWN, 1)
	rig.owner(rig.body(vector.create(0, 50, 0), 0, TICK))
	rig.frames(2)
	rig.step()

	local mounted: Kit.Mounted = Kit.mount(rig)
	if limit then
		mounted.require(mounted.config).exploits.hold = limit
	end

	local switch: (on: boolean) -> () =
		mounted.require(mounted.exploits.LagSwitch).start({ client = rig.handle, shared = rig.shared })

	return rig, switch
end

return function (): (boolean, string | nil)
	local rig: any, switch: (on: boolean) -> () = rigged(nil)
	local before: number = #rig.moves
	local last: number = rig.moves[before].command

	switch(true)
	rig.frames(HELD)
	rig.step()
	if #rig.moves ~= before then
		return false, `{#rig.moves - before} Moves reached the server while the switch held them`
	end

	switch(false)
	rig.step()
	if #rig.moves ~= before + HELD then
		return false, `Off released {#rig.moves - before} Moves, not the {HELD} held`
	end

	for index: number = 1, HELD do
		local move: any = rig.moves[before + index]
		if move.command ~= last + index then
			return false, `Released Move {index} carries command {move.command}, not {last + index}, oldest first`
		elseif move.count == 0 then
			return false, `Released Move {index} carries no commands`
		end
	end

	rig.frames(1)
	rig.step()
	if #rig.moves ~= before + HELD + 1 or rig.moves[#rig.moves].command ~= last + HELD + 1 then
		return false, "After the release the next Move didn't go straight out"
	end

	-- Past the limit the oldest go, so the newest the limit allows are what is released
	local capped: any, capSwitch: (on: boolean) -> () = rigged(LIMIT)
	local start: number = #capped.moves
	local newest: number = capped.moves[start].command + HELD

	capSwitch(true)
	capped.frames(HELD)
	capSwitch(false)
	capped.step()
	if #capped.moves ~= start + LIMIT then
		return false, `Held past a limit of {LIMIT}, {#capped.moves - start} Moves were released`
	elseif capped.moves[#capped.moves].command ~= newest then
		return false,
			`The last Move released past the limit carries {capped.moves[#capped.moves].command}, not {newest}`
	end

	return true, nil
end
