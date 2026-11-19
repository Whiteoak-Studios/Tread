--[[
    How a bot steers: each tick's command filled from its seeded program,
    standing idle, or roaming an area from one random goal to the next as
    the A0 arm's bots walk theirs
--]]

--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Packages = ReplicatedStorage.Packages

local Tread = require(Packages.Tread)

local Config = require(ServerScriptService.Server.Bots.Config)
local Seeded = require(ServerScriptService.Server.Bots.Seeded)

local ARRIVE: number = require(ServerScriptService.Server.Bots.Config).roam.arrive
local PATIENCE: number = require(ServerScriptService.Server.Bots.Config).roam.patience

type Area = Config.Area
type Command = Tread.Command
type Seeded = Seeded.Seeded

-- Fills the command a bot is about to send for a tick, from where its body last stood
export type Steer = (command: Command, tick: number, position: vector) -> ()

-- How a roaming bot walks
export type Gait = {
	speed: number, -- Studs a second it covers, which its patience with a goal counts from
	rate: number, -- Ticks a second
	sprint: boolean,
	crouch: boolean,
	long: boolean, -- Whether it sends a move longer than 1, a raw diagonal, as a speed cheat would
}

local Programs = {}

--[[
    A bot that sends every input at rest, tick after tick
--]]

function Programs.idle(): Steer
	return function (_: Command, _: number, _: vector) end
end

-- A random ground point inside an area, its height the area's
local function pointIn(area: Area, seeded: Seeded): vector
	local halfWidth: number = area.size.X / 2
	local halfDepth: number = area.size.Y / 2
	local x: number = seeded:number(-halfWidth, halfWidth)
	local z: number = seeded:number(-halfDepth, halfDepth)

	return vector.create(area.center.X + x, area.center.Y, area.center.Z + z)
end

--[[
    A bot that walks to a random point of the area, and on reaching it, or
    once twice the straight walk's time has passed, on to the next, its
    goals drawn from its own seeded generator so a seed repeats its path
--]]

function Programs.roam(area: Area, seeded: Seeded, gait: Gait): Steer
	if not (gait.speed > 0 and gait.rate > 0) then
		error(`Programs.roam takes a gait whose speed and rate are above 0, not {gait.speed} and {gait.rate}`, 2)
	end

	local goal: vector? = nil
	local giveUp: number = 0 -- The tick the bot gives up on its goal at

	return function (command: Command, tick: number, position: vector)
		local current: vector? = goal
		local offset: vector = current and current - position or vector.zero
		local distance: number = math.sqrt(offset.x * offset.x + offset.z * offset.z)

		if not current or distance <= ARRIVE or tick >= giveUp then
			local chosen: vector = pointIn(area, seeded)
			goal = chosen
			offset = chosen - position
			distance = math.sqrt(offset.x * offset.x + offset.z * offset.z)
			giveUp = tick + math.ceil(distance / gait.speed * gait.rate * PATIENCE)
		end

		-- The step's yaw 0 looks along -Z and a quarter turn along -X
		command.yaw = math.atan2(-offset.x, -offset.z)
		command.forward = 1
		command.sprint = gait.sprint
		command.crouch = gait.crouch

		if gait.long then
			command.right = 1
		end
	end
end

return Programs
