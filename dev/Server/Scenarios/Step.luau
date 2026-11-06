--[[
    Runs the step's trials on engine casts over its fixture parts, built under
    Workspace.SpikeFixtures and removed whatever happens, then its parity run
    on Lune's pure casts, which must hash to what Lune's own run gives
--]]

--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local Ceiling = require(ServerScriptService.Fixtures.Step.Ceiling)
local Engine = require(ReplicatedStorage.Packages.Tread.Step.Engine)
local Geometry = require(ServerScriptService.Fixtures.Step.Geometry)
local Parity = require(ServerScriptService.Fixtures.Step.Parity)
local State = require(ReplicatedStorage.Packages.Tread.Step.State)
local Ticks = require(ServerScriptService.Fixtures.Step.Ticks)

local SEPARATOR: string = "; " -- Between the problems in one report

type Collision = State.Collision
type Piece = Geometry.Part

-- Builds every fixture part, anchored and collidable, into the folder
local function build(folder: Folder)
	for _, piece: Piece in Ceiling.parts do
		local part: Part = Instance.new("Part")
		part.Name = piece.name
		part.Anchored = true
		part.CanCollide = true
		part.CanQuery = true
		part.CanTouch = false
		part.Size = Engine.toVector3(piece.size)
		part.CFrame = CFrame.new(Engine.toVector3(piece.center)) * CFrame.Angles(0, 0, math.rad(piece.tilt))
		part.Parent = folder
	end
end

--[[
    The parity run here against Lune's hash, and a run with one bit flipped
    against it too, which must differ, or the comparison tells nothing apart
--]]

local function parity(problems: { string })
	local hash: number = Parity.run(false)
	if hash ~= Parity.expected then
		table.insert(problems, `the parity run hashed to {hash} here, where Lune's run gives {Parity.expected}`)
	end

	local flipped: number = Parity.run(true)
	if flipped == hash then
		table.insert(problems, `the parity run with one bit flipped hashed to {flipped} too`)
	end

	print(`Step parity: this server's hash {hash}, Lune's {Parity.expected}, flipped {flipped}`)
end

return function (): (boolean, string | nil)
	local problems: { string } = {}

	local root: Instance? = Workspace:FindFirstChild("SpikeFixtures")
	local madeRoot: boolean = root == nil
	if not root then
		local made: Folder = Instance.new("Folder")
		made.Name = "SpikeFixtures"
		made.Parent = Workspace
		root = made
	end

	local folder: Folder = Instance.new("Folder")
	folder.Name = "StepTicks"
	build(folder)
	folder.Parent = root

	local made: { Collision } = {}
	local ran: boolean, failure: any = pcall(function ()
		local casts: Collision = Engine.collision({ folder })
		table.insert(made, casts)

		for _, name: string in Ticks.names do
			local passed: boolean, reason: string? = Ticks.run(name, casts)
			if not passed then
				table.insert(problems, `engine casts: {reason or name}`)
			end
		end

		parity(problems)
	end)

	if not ran then
		table.insert(problems, `the trials threw: {failure}`)
	end

	-- Everything it made goes, the overlap probe's camera included, whatever the trials did
	for _, collision: Collision in made do
		collision.destroy()
	end

	folder:Destroy()
	if madeRoot and root and #root:GetChildren() == 0 then
		root:Destroy()
	end

	if Workspace:FindFirstChild("TreadProbe") then
		table.insert(problems, "an overlap probe's camera was left in Workspace")
	end

	if #problems > 0 then
		return false, table.concat(problems, SEPARATOR)
	end

	return true, nil
end
