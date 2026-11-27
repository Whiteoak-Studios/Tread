--[[
    What the client probes' workers and their probe share: the topics, the
    marks and samples a worker hands back, the frame events it reads, its
    hold, and a set of stand-in rigs whose legs it bends and writes
--]]

--!strict
--!native
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Packages = ReplicatedStorage.Packages

local Animate = require(Packages.Tread.Client.Rigs.Animate)
local Bend = require(script.Parent.Bend)

local JOINTS: number = 3 -- A leg's joints in a set, its hip, knee and ankle in that order

type Place = Animate.Place

-- The target's rise above its rest at each step, which cycles through count values spacing studs apart from base
export type Rise = {
	base: number,
	spacing: number,
	count: number,
}

-- A set of stand-in rigs' legs, every rig built from one template, so they share its places
export type Set = {
	places: { Place },
	roots: { AnimationConstraint }, -- Each rig's Root joint, whose pose its legs hang from
	joints: { AnimationConstraint }, -- Each leg's hip, knee and ankle in turn, rig by rig, leg by leg
	transforms: { CFrame }, -- What the last solve gave each of those joints, which a write puts on them
	part: BasePart, -- The first rig's root part, which a read of the foot's rise measures from
	foot: BasePart, -- That rig's first leg's foot
}

local Work = {
	CORES = "Cores", -- P6's batch: its round, the loop's passes, the loop buffer's bytes and the marks table
	LAND = "Land", -- A landing arm: the frame event's name, the hold in seconds and the counters table
	BEND = "Bend", -- A bend arm: the worker's rigs, the joints' names by logical joint, the counters and the rise
	STOP = "Stop", -- An arm's end: the results table the worker's samples go into, at its index

	-- The attributes on a worker's Actor
	WORKER = "Worker", -- Its index from 1, which only a clone the probe parents carries
	BOUND = "Bound", -- Set once it has bound every topic
	ARMED = "Armed", -- Set once its bend arm's callback is connected, and cleared when the arm ends

	-- A batch's fields in the marks table, at (index - 1) * FIELDS plus each, the times by os.clock()
	START = 1,
	FINISH = 2,
	ROUND = 3, -- Written last, so its round there means both times are in
	FIELDS = 3,

	-- The frame events the probe counts in the counters table, each under its own name, in the frame's order
	EVENTS = { "PreRender", "PreAnimation", "PreSimulation", "PostSimulation" },
	STEPPED = "PostSimulation", -- The one whose count numbers a bend arm's steps, each step the one after it

	-- A landing callback's sample in a worker's samples: its start, the end of its hold and its resume once
	-- synchronized, then each event's count read before it synchronized, and again once it had, in EVENTS' order
	LANDING = { START = 1, SPUN = 2, SYNCED = 3, BEFORE = 4, AFTER = 8, STRIDE = 11 },

	-- A bend callback's sample: the step it bent, its start, the end of its solve, its resume once synchronized and the
	-- end of its writes, and the PostSimulation count read before it synchronized and again once it had
	BENDING = { STEP = 1, START = 2, SOLVED = 3, SYNCED = 4, WRITTEN = 5, BEFORE = 6, AFTER = 7, STRIDE = 7 },
}

-- Each frame event the probe counts by its name, read from RunService only when asked for
function Work.signals(): { [string]: RBXScriptSignal<number> }
	return {
		PreRender = RunService.PreRender,
		PreAnimation = RunService.PreAnimation,
		PreSimulation = RunService.PreSimulation,
		PostSimulation = RunService.PostSimulation,
	}
end

-- Holds the thread busy for that many seconds by os.clock(), with no engine call, giving how often it read the clock
function Work.busy(seconds: number): number
	local finish: number = os.clock() + seconds
	local reads: number = 0

	repeat
		reads += 1
	until os.clock() >= finish

	return reads
end

-- A rig's joint instances by logical joint, each found by the name the joints map gives it
function Work.joints(rig: Model, names: { [string]: string }): { [string]: AnimationConstraint }
	local joints: { [string]: AnimationConstraint } = {}
	for logical: string, name: string in names do
		joints[logical] = rig:FindFirstChild(name, true) :: AnimationConstraint
	end

	return joints
end

--[[
    The set of those rigs' legs: the places Tread measures from the first
    rig's joints, which every rig shares, each rig's Root and leg joints,
    and a Transform held for each of those until a solve fills it
--]]

function Work.set(rigs: { Model }, names: { [string]: string }): Set
	local first: Model = rigs[1]
	local part: BasePart = first.PrimaryPart :: BasePart
	local places: { Place } = Animate.places(part, Work.joints(first, names))
	local roots: { AnimationConstraint } = {}
	local joints: { AnimationConstraint } = {}

	for _, rig: Model in rigs do
		local own: { [string]: AnimationConstraint } = Work.joints(rig, names)
		table.insert(roots, own.Root)

		for _, place: Place in places do
			table.insert(joints, own[place.hip])
			table.insert(joints, own[place.knee])
			table.insert(joints, own[place.ankle])
		end
	end

	local transforms: { CFrame } = table.create(#joints, CFrame.identity)
	local foot: BasePart = (joints[JOINTS].Attachment1 :: Attachment).Parent :: BasePart

	return { places = places, roots = roots, joints = joints, transforms = transforms, part = part, foot = foot }
end

-- The target's rise above its rest at a step
function Work.height(rise: Rise, step: number): number
	return rise.base + rise.spacing * (step % rise.count)
end

--[[
    Solves every leg of the set to its target, its rest risen by the height
    given, from its rig's hips' pose this step, keeping each joint's
    Transform for a write. It reads the joints and writes none, so it may
    run desynchronized
--]]

function Work.solve(set: Set, height: number)
	local lift: vector = vector.create(0, height, 0)
	local places: { Place } = set.places
	local transforms: { CFrame } = set.transforms
	local legs: number = #places

	for rig: number, root: AnimationConstraint in set.roots do
		local px: number, py: number, pz: number, r00: number, r01: number, r02: number, r10: number, r11: number, r12: number, r20: number, r21: number, r22: number =
			root.Transform:GetComponents()

		local tx: vector = vector.create(r00, r10, r20)
		local ty: vector = vector.create(r01, r11, r21)
		local tz: vector = vector.create(r02, r12, r22)
		local tp: vector = vector.create(px, py, pz)

		for leg: number, place: Place in places do
			local at: number = ((rig - 1) * legs + leg - 1) * JOINTS
			transforms[at + 1], transforms[at + 2], transforms[at + 3] =
				Bend.solve(place, place.rest + lift, tx, ty, tz, tp)
		end
	end
end

-- Puts the last solve's Transforms on the set's joints, which only a synchronized thread may do
function Work.write(set: Set)
	local transforms: { CFrame } = set.transforms
	for index: number, joint: AnimationConstraint in set.joints do
		joint.Transform = transforms[index]
	end
end

-- How far the first rig's first foot stands above where it rests, in its root part's space
function Work.lifted(set: Set): number
	return set.part.CFrame:PointToObjectSpace(set.foot.CFrame.Position).Y - set.places[1].foot.Y
end

return Work
