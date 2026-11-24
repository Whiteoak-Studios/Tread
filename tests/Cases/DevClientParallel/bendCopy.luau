--[[
    The probes' copy of the leg bend solves the same three Transforms Tread's
    layer writes, for legReaches' three targets on the rig fixture, and a set
    of the rig solves, writes and reads its foot's rise as Tread would bend it
--]]

--!strict
local roblox: any = require("@lune/roblox") -- Its typedefs leave out the datatypes

local Mount = require("../../Fixtures/DevClientParallel/Mount")

local CFrame: any = roblox.CFrame

local TOLERANCE: number = 1e-9 -- Studs, or units of an axis, two Transforms may sit apart
local FOOT: number = 1e-4 -- Studs the foot's read rise may sit from the rise, legReaches' tolerance for an ankle
local RISE: number = 1 -- legReaches' step under the left foot
local LOWERED: number = 0.6 -- Studs its hips' pose drops them
local ASIDE: vector = vector.create(0.3, 0.6, -0.4) -- Its target set aside: right, up and ahead
local LIFT: number = 0.3 -- The set's own rise, under both feet

-- How far apart two CFrames sit, by their places and each axis
local function apart(first: any, second: any): number
	return math.max(
		(first.Position - second.Position).Magnitude,
		(first.XVector - second.XVector).Magnitude,
		(first.YVector - second.YVector).Magnitude,
		(first.ZVector - second.ZVector).Magnitude
	)
end

-- A pose's rotation columns and move, as the layer reads the hips' pose
local function columns(pose: any): (vector, vector, vector, vector)
	local px: number, py: number, pz: number, r00: number, r01: number, r02: number, r10: number, r11: number, r12: number, r20: number, r21: number, r22: number =
		pose:GetComponents()

	return vector.create(r00, r10, r20),
		vector.create(r01, r11, r21),
		vector.create(r02, r12, r22),
		vector.create(px, py, pz)
end

return function (): (boolean, string | nil)
	local mounted: Mount.Mounted = Mount()
	local dataModel: any = mounted.loaded.game
	local fixtures: any = dataModel:GetService("ServerScriptService").Fixtures
	local packages: any = dataModel:GetService("ReplicatedStorage").Packages
	local Animate: any = mounted.loaded.require(packages.Tread.Client.Rigs.Animate)
	local Legs: any = mounted.loaded.require(fixtures.Rigs.Legs)
	local RigFixture: any = mounted.loaded.require(fixtures.Rigs.Rig)
	local Bend: any = mounted.Bend
	local Work: any = mounted.Work

	local rig: any, joints: any = Legs.rig()
	local animated: any = Legs.animated(rig, joints)
	animated.planted = true

	-- Lune's Instances keep a written Transform only to about 1e-5, so the layer writes its legs into stand-ins that
	-- keep each one as it came, while the hips' pose is still read off the rig's Root
	for _, leg: any in animated.legs do
		leg.hip = { Name = leg.place.hip, Transform = CFrame.identity }
		leg.knee = { Name = leg.place.knee, Transform = CFrame.identity }
		leg.ankle = { Name = leg.place.ankle, Transform = CFrame.identity }
	end

	-- Why a leg's copied solve missed the Transforms the layer just wrote, nil when it didn't
	local function missed(when: string): string?
		local tx: vector, ty: vector, tz: vector, tp: vector = columns(joints.Root.Transform)
		for _, leg: any in animated.legs do
			local hip: any, knee: any, ankle: any = Bend.solve(leg.place, leg.target, tx, ty, tz, tp)
			local checked: { { name: string, solved: any, written: any } } = {
				{ name = leg.place.hip, solved = hip, written = leg.hip.Transform },
				{ name = leg.place.knee, solved = knee, written = leg.knee.Transform },
				{ name = leg.place.ankle, solved = ankle, written = leg.ankle.Transform },
			}

			for _, pair: { name: string, solved: any, written: any } in checked do
				local off: number = apart(pair.solved, pair.written)
				if off > TOLERANCE then
					return `{when}, the copy solved {pair.name} {off} from what the layer wrote`
				end
			end
		end

		return nil
	end

	-- 1) legReaches' three targets: over the step, under lowered hips, and set aside
	local left: any, right: any = animated.legs[1], animated.legs[2]
	left.planted, right.planted = true, true
	left.target = left.place.rest + vector.create(0, RISE, 0)
	right.target = right.place.rest

	Animate.layer(animated)
	local stepped: string? = missed("Over the step")

	joints.Root.Transform = CFrame.new(0, -LOWERED, 0)
	Animate.layer(animated)
	local lowered: string? = missed("Under lowered hips")

	joints.Root.Transform = CFrame.identity
	right.target = right.place.rest + ASIDE
	Animate.layer(animated)
	local aside: string? = missed("Toward a target aside")

	local copied: string? = stepped or lowered or aside
	if copied then
		return false, copied
	end

	-- 2) A set of the rig solves both legs to one rise as the layer bends them, under lowered hips, and writes it
	local set: any = Work.set({ rig }, RigFixture.joints)
	joints.Root.Transform = CFrame.new(0, -LOWERED, 0)
	left.target = left.place.rest + vector.create(0, LIFT, 0)
	right.target = right.place.rest + vector.create(0, LIFT, 0)

	Work.solve(set, LIFT)
	Animate.layer(animated)

	-- The set holds each rig's legs in the layer's order, a leg's hip, knee and ankle in turn
	local layered: { any } = {}
	for _, leg: any in animated.legs do
		table.insert(layered, leg.hip)
		table.insert(layered, leg.knee)
		table.insert(layered, leg.ankle)
	end

	for index: number, written: any in layered do
		local off: number = apart(set.transforms[index], written.Transform)
		if off > TOLERANCE then
			return false, `The set solved {written.Name} {off} from what the layer wrote`
		end
	end

	-- Its write, into stand-ins that keep each Transform as it came, puts each one on its own joint
	local instances: { any } = set.joints
	set.joints = {}
	for _, joint: any in instances do
		table.insert(set.joints, { Name = joint.Name, Transform = CFrame.identity })
	end

	Work.write(set)
	for index: number, joint: any in set.joints do
		if apart(set.transforms[index], joint.Transform) > 0 then
			return false, `The set's write left {joint.Name} off what it solved`
		end
	end

	set.joints = instances

	-- 3) Under the hips at rest, the foot its joints put where the bend does reads the set's rise
	joints.Root.Transform = CFrame.identity
	Work.solve(set, LIFT)
	Work.write(set)

	local posed: any = Legs.posed(rig, joints, set.places[1])
	set.foot.CFrame = posed.foot

	local lifted: number = Work.lifted(set)
	if math.abs(lifted - LIFT) > FOOT then
		return false, `The foot read {lifted} studs up, not the set's {LIFT}`
	end

	return true, nil
end
