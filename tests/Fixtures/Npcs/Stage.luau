--[[
    The NPC stage the Npcs cases run: a server's world over the step's
    fixture geometry, and the modules beside Npcs a case reads, all from one
    environment, with every landing and report the stage gives kept
--]]

--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Casts = require(script.Parent.Parent.Step.Collision)
local Constants = require(ReplicatedStorage.Packages.Tread.Constants)
local Geometry = require(script.Parent.Parent.Step.Geometry)
local Npcs = require(ReplicatedStorage.Packages.Tread.Server.Npcs)
local Range = require(ReplicatedStorage.Packages.Tread.Server.Range)
local Reports = require(ReplicatedStorage.Packages.Tread.Server.Reports)
local Scene = require(script.Parent.Parent.Step.Scene)
local Slots = require(ReplicatedStorage.Packages.Tread.Server.Slots)
local State = require(ReplicatedStorage.Packages.Tread.Step.State)
local Step = require(ReplicatedStorage.Packages.Tread.Step)

type Npc = Npcs.Npc
type Order = Npcs.Order
type World = State.World

type Landing = { npc: Npc, speed: number }
type Report = { player: any, kind: string, measurement: number | string }

local Stage = {
	Npcs = Npcs,
	Range = Range,
	Reports = Reports,
	Slots = Slots,
	State = State,
	Step = Step,
	geometry = Geometry,
	world = Scene.world(Casts(Geometry.parts)) :: World,
	resting = Geometry.floor + Constants.SKIN, -- Feet at rest on the fixture floor
	landings = {} :: { Landing },
	reports = {} :: { Report },
}

--[[
    Starts the slot table with no reserve and Npcs on the stage's world,
    keeping every landing and report for the case. The connection lasts as
    long as the case's environment, which is thrown away with the case
--]]

function Stage.start()
	Slots.start(0)

	Reports.connect(function (player: any, kind: string, measurement: number | string)
		table.insert(Stage.reports, { player = player, kind = kind, measurement = measurement })
	end)

	Npcs.start(Stage.world, function (npc: Npc, speed: number)
		table.insert(Stage.landings, { npc = npc, speed = speed })
	end)
end

-- A command an NPC is issued, with no input and looking along yaw 0
function Stage.order(): Order
	return {
		forward = 0,
		right = 0,
		jump = false,
		crouch = false,
		sprint = false,
		aim = false,
		yaw = 0,
		pitch = 0,
		lean = 0,
		headYaw = 0,
		headPitch = 0,
		fields = {},
	}
end

return Stage
