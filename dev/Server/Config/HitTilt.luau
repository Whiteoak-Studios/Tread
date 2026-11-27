--[[
    The HitTilt scenario's numbers: where it lays its floor and stands the
    DevRig, the aim its NPC takes, how close each check must come, and how
    long each of its waits may take before it fails
--]]

--!strict
return {
	center = Vector3.new(-300, 1010, 1000), -- The floor's top, beside the staff scenarios' and inside the 1,024-stud window
	rig = Vector3.new(12, 4, 0), -- Where the DevRig's pivot stands from the center, clear of the NPC and over the floor

	pitch = math.pi / 3, -- Radians the NPC aims up by, and the DevRig's Waist is turned by
	yaw = 0.6, -- Radians the NPC faces
	lean = 10, -- Degrees it leans right by

	above = 2, -- Studs past the head's top end each ray down starts
	close = 0.01, -- Studs a placed point may sit from Roblox's own composition, past the history's quanta
	gap = 0.25, -- Studs the DevRig's turned head may sit from where Shapes.place puts its rest point

	waits = {
		settle = 5, -- Seconds the NPC may take to land on the floor
		steps = 5, -- Ticks after the command before the history is read, so the lean has eased in
		beats = 1, -- Heartbeats after each change to the DevRig before it is read
	},
}
