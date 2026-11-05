--[[
    Boots an arm's server: lays its floors, records its Workspace settings,
    and on a live server runs its whole program once a player has joined
--]]

--!strict
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local Bots = require(ServerScriptService.Arm.Bots)
local Program = require(ServerScriptService.Arm.Program)
local Settings = require(ServerScriptService.Arm.Settings)

Bots.layFloors()
Settings.record()

-- In Studio each run starts from an execute_luau chunk, so the place waits for one
if not RunService:IsStudio() then
	Program.all()
end
