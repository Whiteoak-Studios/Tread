--[[
    While on, each Move goes out as it was, then a second carrying only the
    commands no Move carried before, each a step off to the side, while the
    repeats in later Moves match the first copies; off sends one Move again
--]]

--!strict
local Handle = require("../../Fixtures/Client/Handle")
local Kit = require("../../Fixtures/Exploits/Kit")

local OWN: number = 9
local TICK: number = 100

-- One Move as the server read it: the newest number and each command's side axis
type Heard = { command: number, sides: { number } }

return function (): (boolean, string | nil)
	local rig: any = Handle.new()
	local heard: { Heard } = {}

	-- The server's hook before its listener sees every command's wire values
	rig.server.hooks.afterReceive(
		"Move",
		function (_: any, command: number, _: number, _: number, _: number, commands: { any }): boolean
			local sides: { number } = {}
			for _, wire: any in commands do
				table.insert(sides, wire.moveX)
			end

			table.insert(heard, { command = command, sides = sides })

			return true
		end
	)

	rig.handshake()
	rig.own(OWN, 1)
	rig.owner(rig.body(vector.create(0, 50, 0), 0, TICK))
	rig.frames(2)
	rig.step()

	local mounted: Kit.Mounted = Kit.mount(rig)
	local switch: (on: boolean) -> () =
		mounted.require(mounted.exploits.Copy).start({ client = rig.handle, shared = rig.shared })

	switch(true)
	rig.frames(1)
	rig.step()
	local start: number = #heard

	rig.frames(1)
	rig.step()
	if #heard ~= start + 2 then
		return false, `One Move with the copy on reached the server as {#heard - start} Moves, not 2`
	end

	local first: Heard, second: Heard = heard[start + 1], heard[start + 2]
	local previous: Heard = heard[start - 1] -- The first copies of the Move before
	if second.command ~= first.command or #second.sides ~= 1 then
		return false, `The second Move carries {#second.sides} commands from {second.command}, not the one new command`
	elseif math.abs(second.sides[1] - first.sides[1]) ~= 1 then
		return false, `The second copy's side axis is {second.sides[1]}, not a step off the first's {first.sides[1]}`
	elseif first.sides[2] ~= previous.sides[1] then
		return false, "A repeat of an earlier command went out differing from its first copy"
	end

	switch(false)
	rig.frames(1)
	rig.step()
	if #heard ~= start + 3 then
		return false, `With the copy off one Move reached the server as {#heard - start - 2}`
	end

	return true, nil
end
