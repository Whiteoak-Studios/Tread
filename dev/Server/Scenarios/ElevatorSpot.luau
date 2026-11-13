--[[
    Moves the first real player's character to the test elevator's press
    spot, facing -Z as a fresh spawn does, so one press of the elevator's
    key with the look left as the spawn gave it meets the call button
--]]

--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local Packages = ReplicatedStorage.Packages

local Tread = require(Packages.Tread)

local Elevator = require(ReplicatedStorage.Shared.Dev.Elevator)
local Game = require(ServerScriptService.Server.Game)

local SECONDS: number = 10 -- The longest the wait for the teleport to land runs before it fails

return function (): (boolean, string | nil)
	local handle: Tread.Server = Game.get()
	local spot: Vector3 = Elevator.spot

	local character: Tread.Character? = nil
	for _, joined: Player in Players:GetPlayers() do
		character = Game.characterOf(joined)
		if character then
			break
		end
	end

	if not character then
		return false, "no player has a character the dev game holds to move to the press spot"
	end

	local moved: Tread.Character = character
	local player: Player | Tread.Bot = moved.player
	local landed: boolean = false
	local stop: () -> () = handle:onTeleported(function (teleported: Tread.Character)
		if teleported == moved then
			landed = true
		end
	end)

	-- A CFrame with no turn looks along -Z, the way every spawn point faces
	local sent: boolean, failure: any = pcall(moved.teleport, moved, CFrame.new(spot))
	if not sent then
		stop()

		return false, `{player.Name}'s teleport to the press spot {spot} threw: {failure}`
	end

	local deadline: number = os.clock() + SECONDS
	while not landed and os.clock() < deadline do
		RunService.Heartbeat:Wait()
	end

	stop()

	if not landed then
		return false, `{player.Name}'s teleport to the press spot {spot} did not land within {SECONDS} s`
	end

	local line: string =
		`{player.Name} stands at the press spot {spot}, facing -Z at the button {Elevator.button.Position}`
	print(`ElevatorSpot: {line}`)

	return true, line
end
