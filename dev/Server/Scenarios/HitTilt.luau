--[[
    The aim pitch's tilt of the hit shapes, live: an NPC aiming up on a floor
    of its own, its history's shapes against Roblox's own CFrames and a ray
    test, and the DevRig's Waist turned the same way against Shapes.place
--]]

--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")
local Packages = ReplicatedStorage.Packages

local Tread = require(Packages.Tread)

local Ballistics = require(ReplicatedStorage.Shared.Dev.Ballistics)
local Command = require(Packages.Tread.Codec.Command)
local Constants = require(Packages.Tread.Constants)
local Engine = require(Packages.Tread.Step.Engine)
local Shapes = require(Packages.Tread.Step.Shapes)

local Game = require(ServerScriptService.Server.Game)
local Testbed = require(ServerScriptService.Server.Scenarios.Staff.Testbed)

local CENTER: Vector3 = require(ServerScriptService.Server.Config.HitTilt).center
local RIG_AT: Vector3 = require(ServerScriptService.Server.Config.HitTilt).rig
local PITCH: number = require(ServerScriptService.Server.Config.HitTilt).pitch
local YAW: number = require(ServerScriptService.Server.Config.HitTilt).yaw
local LEAN: number = require(ServerScriptService.Server.Config.HitTilt).lean
local ABOVE: number = require(ServerScriptService.Server.Config.HitTilt).above
local CLOSE: number = require(ServerScriptService.Server.Config.HitTilt).close
local GAP: number = require(ServerScriptService.Server.Config.HitTilt).gap
local SETTLE: number = require(ServerScriptService.Server.Config.HitTilt).waits.settle
local STEPS: number = require(ServerScriptService.Server.Config.HitTilt).waits.steps
local BEATS: number = require(ServerScriptService.Server.Config.HitTilt).waits.beats
local NAME: string = "HitTilt"
local TEMPLATE: string = "DevRig" -- The dev place's R15 model in ReplicatedStorage, which the dev client draws every rig from
local HEAD_PART: string = "Head"
local WAIST_JOINT: string = "Waist" -- The DevRig's AnimationConstraint for the waist, named for its joint
local RIG_FOLDER: string = "HitTiltRig" -- The Workspace folder the DevRig's clone stands in
local POSTURE: string = "Stand"
local HEAD: string = "head" -- The dev table's head zone
local READS: number = 1 -- Relay ticks the history is read on
local AHEAD: number = 0 -- A yaw that faces -Z, as the NPC is built facing and the DevRig stands
local DOWN: Vector3 = Vector3.new(0, -1, 0)
local SEPARATOR: string = "; " -- Between the parts of a report

-- Waits for a promise and gives whether it held, a failure becoming a problem
local function held(promise: any, problems: { string }): boolean
	local ok: boolean, failure: any = promise:await()
	if not ok then
		table.insert(problems, tostring(failure))
	end

	return ok
end

-- The configured number of Heartbeats, one after another, each on its own deadline
local function beats(testbed: Testbed.Testbed, problems: { string }): boolean
	for _ = 1, BEATS do
		if not held(testbed:heartbeat(), problems) then
			return false
		end
	end

	return true
end

-- The frame a sample's feet and yaw stand in, the step's yaw turning -Z toward -X as CFrame.Angles turns about Y
local function standing(sample: Tread.Sample): CFrame
	return CFrame.new(sample.position) * CFrame.Angles(0, sample.yaw, 0)
end

-- The frame the upper body turns in, at the waist above the feet, by the lean first and the pitch second
local function tilted(sample: Tread.Sample, waist: number, lean: number): CFrame
	return standing(sample) * CFrame.new(0, waist, 0) * CFrame.Angles(PITCH, 0, -math.rad(lean))
end

-- Where Roblox's own CFrames put an own-space point of the sample's shapes: tilted at the waist only above it
local function composed(sample: Tread.Sample, at: Vector3, waist: number, lean: number): Vector3
	if at.Y > waist then
		return tilted(sample, waist, lean) * Vector3.new(at.X, at.Y - waist, at.Z)
	end

	return standing(sample) * at
end

--[[
    The NPC built on the floor, landed, then aiming up, turned and leaning,
    and its sample read on a relay tick once its lean has eased in, or nil
    when a wait failed
--]]

local function aim(testbed: Testbed.Testbed, problems: { string }): Tread.Sample?
	local server: Tread.Server = Game.get()
	local npc: Tread.Npc = server:createNpc(testbed:place(Vector3.zero, AHEAD))
	testbed:own(function ()
		npc:destroy()
	end)

	local landed: boolean = held(
		testbed:waitFor("the NPC to land", function (_: number): boolean
			return npc:getState().grounded
		end, SETTLE),
		problems
	)

	if not landed then
		return nil
	end

	local command: Tread.Command = Command.new()
	command.yaw = YAW
	command.pitch = PITCH
	command.lean = LEAN
	npc:command(command)

	if not held(testbed:ticks(STEPS), problems) then
		return nil
	end

	local found: Tread.Sample? = nil
	local sampled: boolean, failure: any = testbed
		:sample(READS, function (relayTick: number): string?
			found = server:sampleAt(npc, relayTick)
			if found == nil then
				return "the NPC had no sample"
			end

			return nil
		end)
		:await()

	local sample: Tread.Sample? = found
	if not sampled then
		table.insert(problems, tostring(failure))

		return nil
	elseif failure or not sample then
		table.insert(problems, `the history: {failure}`)

		return nil
	end

	return sample
end

--[[
    The sample's shapes against Roblox's own composition, the points at or
    below the waist untilted, the head back along the facing, and a ray down
    the tilted axis striking the head where one down the upright line does not
--]]

local function history(
	sample: Tread.Sample,
	shared: Tread.Shared,
	lean: number,
	problems: { string },
	figures: { string }
)
	local stand = shared.hitShapes.Stand
	local waist: number = stand.waist

	if sample.posture ~= POSTURE then
		table.insert(problems, `the NPC's sample was placed {sample.posture}, not {POSTURE}`)

		return
	end

	-- 1) Every placed point beside Roblox's composition, the tilted and the untilted apart
	local worstTilted: number = 0
	local worstUntilted: number = 0
	local points: number = 0

	local function compare(name: string, got: Vector3, at: Vector3)
		local gap: number = (got - composed(sample, at, waist, lean)).Magnitude
		points += 1

		if at.Y > waist then
			worstTilted = math.max(worstTilted, gap)
		else
			worstUntilted = math.max(worstUntilted, gap)
		end

		if gap > CLOSE then
			table.insert(problems, `the {name} sat {gap} studs from Roblox's composition`)
		end
	end

	compare("body's bottom", sample.body.from, stand.body.from)
	compare("body's top", sample.body.to, stand.body.to)

	for name: string, shape: Tread.Shape in stand.zones do
		local placed: Tread.Shape? = sample.zones[name]
		if placed then
			compare(`{name}'s first end`, placed.from, shape.from)
			compare(`{name}'s second end`, placed.to, shape.to)
		else
			table.insert(problems, `the sample placed no {name}`)
		end
	end

	table.insert(
		figures,
		string.format(
			"%d points within %.5f studs of the CFrames above the waist and %.5f at or below it",
			points,
			worstTilted,
			worstUntilted
		)
	)

	-- 2) The head back along the facing from where it would stand upright
	local head: Tread.Shape? = sample.zones[HEAD]
	local given: Tread.Shape? = stand.zones[HEAD]
	if not head or not given then
		table.insert(problems, `the dev table or the sample has no {HEAD}`)

		return
	end

	local back: Vector3 = -standing(sample).LookVector
	local upright: Vector3 = standing(sample) * ((given.from + given.to) / 2)
	local behind: number = ((head.from + head.to) / 2 - upright):Dot(back)
	if not (behind > CLOSE) then
		table.insert(problems, `aiming up, the head sat {behind} studs back along the facing, not behind it`)
	end

	table.insert(figures, string.format("the head sat %.3f studs back along the facing", behind))

	-- 3) A ray down the tilted axis strikes the head; one down the upright line through its old place does not
	local reach: number = given.to.Y - waist + ABOVE
	local axis: Vector3 = tilted(sample, waist, lean).UpVector
	local pivot: Vector3 = standing(sample) * Vector3.new(0, waist, 0)
	local over: Vector3 = standing(sample) * Vector3.new(0, given.to.Y + ABOVE, 0)

	local along: string? = Ballistics.zone(pivot + axis * reach, -axis, reach, sample.body, sample.zones)
	local straight: string? = Ballistics.zone(over, DOWN, reach, sample.body, sample.zones)

	if along ~= HEAD then
		table.insert(problems, `the ray down the tilted axis struck {tostring(along)}, not the {HEAD}`)
	end

	if straight == HEAD then
		table.insert(problems, `the ray down through the upright {HEAD}'s place struck the {HEAD}`)
	end

	table.insert(
		figures,
		`a ray down the tilted axis struck {tostring(along)}, and one down the upright line {tostring(straight)}`
	)
end

-- The DevRig's clone readied as the client's rig pool readies it, with no Animator, since nothing plays on it
local function prepare(template: Model): (Model, BasePart?)
	local made: Model = template:Clone()
	local root: BasePart? = made.PrimaryPart

	for _, item: Instance in made:GetDescendants() do
		if
			item:IsA("Humanoid")
			or item:IsA("BaseScript")
			or item:IsA("BallSocketConstraint")
			or item:IsA("NoCollisionConstraint")
			or item:IsA("Animator")
		then
			item:Destroy()
		elseif item:IsA("BasePart") then
			item.Anchored = item == root
			item.CanCollide = false
			item.CanQuery = false
			item.CanTouch = false
		end
	end

	return made, root
end

--[[
    The DevRig's Waist turned by the lean and the pitch as Tread's layer
    turns it, its head read in its root's space before and after, against
    Shapes.place on a one-point shape at the head's rest point
--]]

local function rig(
	testbed: Testbed.Testbed,
	shared: Tread.Shared,
	lean: number,
	problems: { string },
	figures: { string }
)
	local template: Instance? = ReplicatedStorage:FindFirstChild(TEMPLATE)
	if not template or not template:IsA("Model") then
		table.insert(problems, `ReplicatedStorage.{TEMPLATE} is missing or no Model`)

		return
	end

	local folder: Folder = Instance.new("Folder")
	folder.Name = RIG_FOLDER
	testbed:own(function ()
		folder:Destroy()
	end)

	local model: Model, root: BasePart? = prepare(template)
	model.Parent = folder
	if not root then
		table.insert(problems, `ReplicatedStorage.{TEMPLATE} has no PrimaryPart to anchor`)

		return
	end

	local head: Instance? = model:FindFirstChild(HEAD_PART)
	local joint: Instance? = model:FindFirstChild(WAIST_JOINT, true)
	if not head or not head:IsA("BasePart") or not joint or not joint:IsA("AnimationConstraint") then
		table.insert(problems, `the {TEMPLATE} has no {HEAD_PART} part or no {WAIST_JOINT} AnimationConstraint`)

		return
	end

	local attachment: Attachment? = joint.Attachment0
	if not attachment then
		table.insert(problems, `the {TEMPLATE}'s {WAIST_JOINT} has no Attachment0`)

		return
	end

	model:PivotTo(CFrame.new(CENTER + RIG_AT))
	folder.Parent = Workspace

	if not beats(testbed, problems) then
		return
	end

	-- Own space has the feet at the rig's lowest point, under its root and turned with it
	local box: CFrame, size: Vector3 = model:GetBoundingBox()
	local bottom: number = root.CFrame:PointToObjectSpace(box.Position).Y - size.Y / 2
	local feet: Vector3 = Vector3.new(0, bottom, 0)
	local pivot: number = root.CFrame:PointToObjectSpace(attachment.WorldPosition).Y - bottom
	local rest: Vector3 = root.CFrame:PointToObjectSpace(head.Position) - feet

	joint.Transform = CFrame.Angles(PITCH, 0, -math.rad(lean))

	if not beats(testbed, problems) then
		return
	end

	local turned: Vector3 = root.CFrame:PointToObjectSpace(head.Position) - feet

	local waist: number = shared.hitShapes.Stand.waist
	local point: Tread.Shape = { from = rest, to = rest, radius = 0 }
	local from: Shapes.Shapes = Shapes.cross({ body = point, zones = {}, waist = waist })
	local into: Shapes.Shapes = Shapes.cross({ body = point, zones = {}, waist = waist })
	Shapes.place(from, into, vector.zero, AHEAD, lean, PITCH)

	local gap: number = (turned - Engine.toVector3(into.body.from)).Magnitude
	if gap > GAP then
		table.insert(problems, `the DevRig's turned head sat {gap} studs from Shapes.place's, past {GAP}`)
	end

	table.insert(
		figures,
		string.format(
			"the DevRig's Waist pivot stands %.3f studs above its lowest point, the table's %.3f",
			pivot,
			waist
		)
	)
	table.insert(figures, string.format("its turned head sat %.3f studs from Shapes.place's", gap))
end

local function run(testbed: Testbed.Testbed, problems: { string }, figures: { string })
	local _, shared: Tread.Shared = Game.get()

	-- The lean in the history's whole steps of the limit, as the step quantizes it each tick
	local limit: number = shared.step.lean
	local lean: number = math.round(LEAN / limit * Constants.LEAN_STEPS) * limit / Constants.LEAN_STEPS

	local sample: Tread.Sample? = aim(testbed, problems)
	if sample then
		history(sample, shared, lean, problems, figures)
	end

	rig(testbed, shared, lean, problems, figures)
end

return function (): (boolean, string | nil)
	local built: boolean, made: any = pcall(Testbed.new, NAME, CENTER)
	if not built then
		return false, `its floor could not be laid: {made}`
	end

	local testbed: Testbed.Testbed = made
	local problems: { string } = {}
	local figures: { string } = {}

	local ran: boolean, failure: any = pcall(run, testbed, problems, figures)
	if not ran then
		table.insert(problems, `the checks threw: {failure}`)
	end

	-- Everything it made goes, whatever the checks found
	for _, problem: string in testbed:clean() do
		table.insert(problems, problem)
	end

	local line: string = table.concat(figures, SEPARATOR)
	print(`{NAME}: {line}`)

	if #problems > 0 then
		return false, table.concat(problems, SEPARATOR)
	end

	return true, line
end
