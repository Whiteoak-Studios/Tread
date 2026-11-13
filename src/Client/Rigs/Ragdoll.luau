--[[
    A dying rig's ragdoll on the client's own physics: its joints go limp in
    ball sockets with the game's limits, its torso takes the death's push,
    and it freezes in the pose it settles in
--]]

--!strict
local Workspace = game:GetService("Workspace")

local ROOT: string = "Root" -- The joint to the anchored root, which a ragdoll lets go of and never limits
local GROUP: string = "TreadRagdoll" -- The collision group every ragdoll's parts share, which never collides with itself

-- A joint's limits, degrees: the cone it may tilt in and the twist about its axis
export type Limit = {
	tilt: number,
	twistLower: number,
	twistUpper: number,
}

-- The client settings' bodies block
export type Bodies = {
	radius: number, -- Farther from the body than this when the death arrives draws it lying
	late: number, -- Seconds; a death that arrives later than this after it happened draws the body lying
	minSeconds: number, -- The first settle check
	maxSeconds: number, -- When a ragdoll freezes however it moves
	check: number, -- Seconds between settle checks
	settleSpeed: number, -- Studs a second every part must move slower than to settle
	pushSpeed: number, -- Studs a second the torso is pushed at
	pushUpBias: number, -- How far the push is raised off the attack's direction
	jointLimits: { [string]: Limit }, -- By logical joint, every joint but Root
}

export type Body = {
	parts: { BasePart }, -- The parts its joints moved, each its own assembly now
	machinery: { Instance }, -- What the freeze removes: its joints, their attachments, its sockets and its Animator
	thread: thread?, -- The next settle check, until it freezes
	frozen: boolean,
}

-- Whether GROUP is set up in this world, nil before the first ragdoll asks
local Grouped: boolean? = nil

local Ragdoll = {}

--[[
    Errors naming the first logical joint but Root that the bodies block
    gives no limits for
--]]

function Ragdoll.check(bodies: Bodies, joints: { string })
	for _, name: string in joints do
		if name ~= ROOT and type(bodies.jointLimits[name]) ~= "table" then
			error(`bodies.jointLimits gives no limits for {name}`, 3)
		end
	end
end

--[[
    The velocity the torso is pushed at: along the death's attack direction
    raised by the up bias, at the push speed, and none for a death that
    carries no direction
--]]

function Ragdoll.push(direction: vector?, bodies: Bodies): vector
	if direction == nil or vector.magnitude(direction) == 0 then
		return vector.zero
	end

	local raised: vector = vector.normalize(direction) + vector.create(0, bodies.pushUpBias, 0)
	local length: number = vector.magnitude(raised)
	if length == 0 then
		return vector.zero
	end

	return raised / length * bodies.pushSpeed
end

-- Sets GROUP up the first time a ragdoll needs it, and says whether it could be
local function grouped(): boolean
	if Grouped == nil then
		local made: boolean, problem: any = pcall(function ()
			if not Workspace:IsCollisionGroupRegistered(GROUP) then
				Workspace:RegisterCollisionGroup(GROUP)
			end

			Workspace:CollisionGroupSetCollidable(GROUP, GROUP, false)
		end)

		if not made then
			warn(`Ragdolls collide with themselves, since the {GROUP} collision group could not be set up: {problem}`)
		end

		Grouped = made
	end

	return Grouped == true
end

local function settled(parts: { BasePart }, speed: number): boolean
	for _, part: BasePart in parts do
		if part.AssemblyLinearVelocity.Magnitude >= speed then
			return false
		end
	end

	return true
end

--[[
    Anchors every part of the rig where it lies, with no collision, touch or
    query, and removes the ragdoll's machinery, so a frozen body costs only
    its drawing
--]]

local function freeze(rig: Model, body: Body)
	for _, item: Instance in rig:GetDescendants() do
		if item:IsA("BasePart") then
			item.Anchored = true
			item.CanCollide = false
			item.CanTouch = false
			item.CanQuery = false
		end
	end

	for _, item: Instance in body.machinery do
		item:Destroy()
	end
	table.clear(body.machinery)

	body.frozen = true
end

--[[
    Ragdolls a rig whose tracks have stopped: every joint but Root goes limp
    inside a ball socket on the joint's own attachments, with that joint's
    limits; the parts collide with the world and not each other; Root lets
    go of the anchored root; and the torso takes the push. It freezes at the
    first check from bodies.minSeconds on where it has settled, or at
    bodies.maxSeconds

    @ joints | the rig's own joint instances, by logical name
    @ push | the torso's velocity, from push
--]]

function Ragdoll.start(
	rig: Model,
	joints: { [string]: AnimationConstraint },
	torso: BasePart,
	bodies: Bodies,
	push: vector
): Body
	local body: Body = { parts = {}, machinery = {}, thread = nil, frozen = false }
	local collides: boolean = grouped()

	-- 1) Every joint but Root goes limp in its socket
	for name: string, joint: AnimationConstraint in joints do
		local attachment0 = joint.Attachment0 :: Attachment
		local attachment1 = joint.Attachment1 :: Attachment
		table.insert(body.parts, attachment1.Parent :: BasePart)
		table.insert(body.machinery, joint)
		table.insert(body.machinery, attachment0)
		table.insert(body.machinery, attachment1)

		if name ~= ROOT then
			local limit: Limit = bodies.jointLimits[name]
			local socket: BallSocketConstraint = Instance.new("BallSocketConstraint")
			socket.Attachment0 = attachment0
			socket.Attachment1 = attachment1
			socket.LimitsEnabled = true
			socket.UpperAngle = limit.tilt
			socket.TwistLimitsEnabled = true
			socket.TwistLowerAngle = limit.twistLower
			socket.TwistUpperAngle = limit.twistUpper
			socket.Parent = attachment1.Parent
			table.insert(body.machinery, socket)

			joint.Enabled = false
		end
	end

	-- 2) The parts collide with the world, in a group that skips itself
	for _, part: BasePart in body.parts do
		part.CanCollide = true
		if collides then
			part.CollisionGroup = GROUP
		end
	end

	-- 3) Root lets go last, so the body falls only once it is all limp
	joints[ROOT].Enabled = false

	local controller: AnimationController? = rig:FindFirstChildOfClass("AnimationController")
	if controller then
		table.insert(body.machinery, controller)
	end

	-- 4) The push, on the torso alone, since every part is an assembly of its own now
	if push ~= vector.zero then
		torso.AssemblyLinearVelocity = Vector3.new(push.x, push.y, push.z)
	end

	local started: number = os.clock()

	local function check()
		body.thread = nil

		local elapsed: number = os.clock() - started
		if elapsed >= bodies.maxSeconds or settled(body.parts, bodies.settleSpeed) then
			freeze(rig, body)
			return
		end

		body.thread = task.delay(math.min(bodies.check, bodies.maxSeconds - elapsed), check)
	end

	body.thread = task.delay(bodies.minSeconds, check)

	return body
end

--[[
    Cancels a ragdoll's next settle check, for a body removed before it
    froze
--]]

function Ragdoll.stop(body: Body)
	local thread: thread? = body.thread
	if thread then
		task.cancel(thread)
		body.thread = nil
	end
end

return Ragdoll
