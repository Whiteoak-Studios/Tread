--[[
    character:teleport sets the body down at the end of the next decode, a
    game's onTeleported callbacks hear it after the handle's own, which
    makes every anti-ESP pair of the slot due at once, one that throws stops
    none of the rest, and a bad place is refused before anything is held
--]]

--!strict
local roblox: any = require("@lune/roblox")

local Rig = require("../../Fixtures/Server/Rig")

local TICKS: number = 4
local CLOSE: number = 0.1 -- Studs the landing may sit from its destination, the skin and a rest included

return function (): (boolean, string | nil)
	local rig: Rig.Rig = Rig.new()
	local server: any = rig:start()
	local AntiEsp: any = rig:require(rig.tread.Server.AntiEsp)

	server:create(rig.mock:addBot("Viewer"), rig:at(0, 0))
	local mover: any = server:create(rig.mock:addBot("Mover"), rig:at(6, 0))
	rig:tick(TICKS)

	local heard: { any } = {}
	local stopThrowing: () -> () = server:onTeleported(function (_: any)
		error("This teleport callback throws on purpose, to show the others still run")
	end)
	local stopHeard: () -> () = server:onTeleported(function (character: any)
		table.insert(heard, character)
	end)

	if pcall(mover.teleport, mover, roblox.CFrame.new(1e9, 0, 0)) then
		return false, "character:teleport took a place past the play bound"
	elseif pcall(mover.teleport, mover, "there") then
		return false, "character:teleport took a string"
	elseif pcall(server.onTeleported, server, "callback") then
		return false, "server:onTeleported took a string"
	end

	-- A tick with nothing moved tests no pair, since visible ones hold
	local tests: number = AntiEsp.counts()
	rig:tick(1)
	if AntiEsp.counts() ~= tests then
		return false, "A tick with nothing moved retested a pair"
	end

	local destination: any = rig:at(-10, 5)
	mover:teleport(destination)
	if #heard ~= 0 then
		return false, "The teleport landed before a tick ran"
	end

	rig:tick(1)

	local root: any = mover:getState().root
	if #heard ~= 1 or heard[1] ~= mover then
		return false, `onTeleported heard {#heard} landings, not the mover's`
	elseif math.abs(root.X - destination.Position.X) > CLOSE or math.abs(root.Z - destination.Position.Z) > CLOSE then
		return false, `The mover landed at {root}, not {destination.Position}`
	elseif not (AntiEsp.counts() >= tests + 2) then
		return false, "The landing made fewer than both of the mover's anti-ESP pairs due"
	end

	stopThrowing()
	stopHeard()
	mover:teleport(rig:at(6, 0))
	rig:tick(1)

	if #heard ~= 1 then
		return false, "A disconnected onTeleported callback still heard a landing"
	end

	return true, nil
end
