--[[
    The leg bend's fixture: the rig fixture's template with its joints, a
    stand-in for the drawn rig the layer bends, and where the joints put a
    leg once its Transforms are written, as the engine poses it
--]]

--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Animate = require(ReplicatedStorage.Packages.Tread.Client.Rigs.Animate)
local Rig = require(script.Parent.Rig)

type Place = Animate.Place

-- Where a leg's joints put it: each pivot, and the foot's frame
export type Posed = {
	hip: Vector3,
	knee: Vector3,
	ankle: Vector3,
	foot: CFrame,
}

local Legs = {}

--[[
    A fresh template of the rig fixture's and its joint instances by
    logical name
--]]

function Legs.rig(): (Model, { [string]: AnimationConstraint })
	local rig: Model = Rig.template()
	local joints: { [string]: AnimationConstraint } = {}
	for logical: string, name: string in Rig.joints do
		joints[logical] = rig:FindFirstChild(name, true) :: AnimationConstraint
	end

	return rig, joints
end

--[[
    What the layer reads of a drawn rig, over a template's own joints: its
    legs from the template's places, unplanted, its waist untilted and an
    Animator that is never throttled
--]]

function Legs.animated(rig: Model, joints: { [string]: AnimationConstraint }): { [string]: any }
	local places: { Place } = Animate.places(rig.PrimaryPart :: BasePart, joints)

	return {
		animator = { EvaluationThrottled = false },
		waist = joints.Waist,
		root = joints.Root,
		tilt = CFrame.identity,
		tilted = false,
		planted = false,
		legs = Animate.legs(joints, places),
	}
end

-- A joint's Part1 frame from its Part0's, as the engine places it, and the joint's pivot
local function after(part0: CFrame, joint: AnimationConstraint): (CFrame, Vector3)
	local mounted: CFrame = part0 * (joint.Attachment0 :: Attachment).CFrame

	return mounted * joint.Transform * (joint.Attachment1 :: Attachment).CFrame:Inverse(), mounted.Position
end

--[[
    Where a leg's joints put its pivots and its foot, from the root part's
    CFrame down through each joint's C0, Transform and C1
--]]

function Legs.posed(rig: Model, joints: { [string]: AnimationConstraint }, place: Place): Posed
	local root: CFrame = (rig.PrimaryPart :: BasePart).CFrame
	local hips: CFrame = after(root, joints.Root)
	local thigh: CFrame, hip: Vector3 = after(hips, joints[place.hip])
	local shin: CFrame, knee: Vector3 = after(thigh, joints[place.knee])
	local foot: CFrame, ankle: Vector3 = after(shin, joints[place.ankle])

	return { hip = hip, knee = knee, ankle = ankle, foot = foot }
end

--[[
    How far a posed leg's knee sits ahead of the line from its hip's pivot
    to its ankle's, along a frame's look, and how far to the frame's right
--]]

function Legs.knee(posed: Posed, frame: CFrame): (number, number)
	local along: Vector3 = (posed.ankle - posed.hip).Unit
	local from: Vector3 = posed.knee - posed.hip
	local offset: Vector3 = from - along * from:Dot(along)

	return offset:Dot(frame.LookVector), offset:Dot(frame.RightVector)
end

--[[
    The widest any axis turns between two frames, in degrees, from the
    chord between the axes, exact near zero
--]]

function Legs.degrees(from: CFrame, to: CFrame): number
	local chord: number = math.max(
		(from.XVector - to.XVector).Magnitude,
		(from.YVector - to.YVector).Magnitude,
		(from.ZVector - to.ZVector).Magnitude
	)

	return math.deg(2 * math.asin(math.min(chord / 2, 1)))
end

--[[
    A point in the world in a rig's root space, as the step's vector, the
    way a leg's target is held
--]]

function Legs.inRoot(rig: Model, point: Vector3): vector
	local relative: Vector3 = (rig.PrimaryPart :: BasePart).CFrame:PointToObjectSpace(point)

	return vector.create(relative.X, relative.Y, relative.Z)
end

return Legs
