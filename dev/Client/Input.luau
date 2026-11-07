--[[
    The dev game's input: keyboard and mouse, and on a touch screen a move
    stick, a look drag and a jump button, sampled into each command Tread
    sends and read each frame as the base look
--]]

--!strict
local Input = {}
Input.__index = Input

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local Packages = ReplicatedStorage.Packages

local Tread = require(Packages.Tread)

local MOUSE_TURN: number = 0.004 -- Radians the look turns for each pixel the mouse moves
local TOUCH_TURN: number = 0.008 -- Radians it turns for each pixel a look drag moves
local PITCH_DEGREES: number = 89 -- The look's pitch either way, short of straight up or down, where the camera has no up
local STICK_RADIUS: number = 60 -- Pixels the stick's thumb travels from where it was touched to a full input
local STICK_SIDE: number = 0.5 -- The share of the screen's width, from the left, where a touch drives the stick
local JUMP_SIZE: number = 96 -- Pixels across the jump button
local JUMP_MARGIN: number = 32 -- Pixels between the jump button and the screen's bottom right corner
local GUI_WAIT: number = 10 -- Seconds the touch controls wait at boot for the player's PlayerGui
local EMPTY_HANDS: number = 0 -- The held hotbar slot's value with nothing in hand, since the dev game has no hotbar
local LEVEL: number = 0 -- The head offset, degrees, since the dev game has no free look to turn the head off the look
local TURN: number = 2 * math.pi -- Radians a turn, which the yaw wraps at

local PITCH_LIMIT: number = math.rad(PITCH_DEGREES)
local RING: number = 2 * STICK_RADIUS -- Pixels across the stick's ring, whose rim a full input reaches
local THUMB: number = STICK_RADIUS -- Pixels across the stick's thumb, half the ring

-- The action each key and mouse button drives, by its KeyCode's name or, for a mouse button, its UserInputType's
local BINDINGS: { [string]: string } = {
	W = "forward",
	S = "back",
	A = "left",
	D = "right",
	Space = "jump",
	LeftShift = "sprint",
	C = "crouch",
	MouseButton2 = "aim",
}

local ACTIONS: { string } = { "forward", "back", "left", "right", "jump", "sprint", "crouch", "aim" }

type Command = Tread.Command

type Fields = {
	_held: { [string]: boolean }, -- Each action's level
	_right: number, -- The move stick's axes, each -1 to 1 and together at most 1 long
	_forward: number,
	_yaw: number, -- The base look, radians, yaw 0 along -Z and a quarter turn along -X
	_pitch: number,
	_stick: InputObject?, -- The touch on the move stick
	_origin: Vector3, -- Where it began
	_drag: InputObject?, -- The touch dragging the look
	_dragged: Vector3, -- Where it was last
	_jump: InputObject?, -- The touch on the jump button
	_ring: Frame?, -- The stick's ring and thumb, shown while it is touched
	_thumb: Frame?,
}

--[[
    Input at rest: no action held, the stick centered and the look level
    along -Z
--]]

function Input.new(): Self
	local held: { [string]: boolean } = {}
	for _, action: string in ACTIONS do
		held[action] = false
	end

	return setmetatable({
		_held = held,
		_right = 0,
		_forward = 0,
		_yaw = 0,
		_pitch = 0,
		_stick = nil :: InputObject?,
		_origin = Vector3.zero,
		_drag = nil :: InputObject?,
		_dragged = Vector3.zero,
		_jump = nil :: InputObject?,
		_ring = nil :: Frame?,
		_thumb = nil :: Frame?,
	}, Input)
end

--[[
    Starts listening to the player's keyboard, mouse and touches, and on a
    touch screen puts up the stick's ring and the jump button. It waits at
    boot for the PlayerGui on a touch screen alone
--]]

function Input.start(self: Self)
	-- Every connection below lives for the client session
	UserInputService.InputBegan:Connect(function (input: InputObject, processed: boolean)
		self:_began(input, processed)
	end)

	UserInputService.InputChanged:Connect(function (input: InputObject, _: boolean)
		self:_changed(input)
	end)

	UserInputService.InputEnded:Connect(function (input: InputObject, _: boolean)
		self:_ended(input)
	end)

	if UserInputService.TouchEnabled then
		self:_controls()
	end
end

--[[
    Holds or lets go of the action a key or mouse button is bound to, by
    its KeyCode's or UserInputType's name. An unbound one does nothing
--]]

function Input.press(self: Self, name: string, down: boolean)
	local action: string? = BINDINGS[name]
	if action then
		self._held[action] = down
	end
end

--[[
    Turns the base look by a drag of so many pixels: right turns right, up
    looks up, with the pitch held short of straight up or down

    @ rate | radians a pixel turns
--]]

function Input.turn(self: Self, dx: number, dy: number, rate: number)
	self._yaw = (self._yaw - dx * rate) % TURN
	self._pitch = math.clamp(self._pitch - dy * rate, -PITCH_LIMIT, PITCH_LIMIT)
end

--[[
    Sets the move stick's axes, a thumb past the stick's rim held at a
    full input along its own direction
--]]

function Input.stick(self: Self, right: number, forward: number)
	local length: number = math.max(math.sqrt(right * right + forward * forward), 1)
	self._right = right / length
	self._forward = forward / length
end

--[[
    Turns the base look to a yaw, level, as a body Tread starts faces
--]]

function Input.face(self: Self, yaw: number)
	self._yaw = yaw % TURN
	self._pitch = 0
end

--[[
    Fills the command Tread sends this tick: the keys' and the stick's move
    axes together, a diagonal held to a full input, the actions' levels, the
    base look and empty hands. Tread reuses the command, so this makes one
    shot list for a command that has none and reuses it from then on
--]]

function Input.sample(self: Self, command: Command)
	local held: { [string]: boolean } = self._held
	local forward: number = self._forward
	local right: number = self._right

	if held.forward then
		forward += 1
	end

	if held.back then
		forward -= 1
	end

	if held.right then
		right += 1
	end

	if held.left then
		right -= 1
	end

	-- Tread reports a move input longer than 1 as tampering, so a diagonal is scaled back to 1
	local length: number = math.max(math.sqrt(forward * forward + right * right), 1)
	command.forward = forward / length
	command.right = right / length
	command.jump = held.jump
	command.crouch = held.crouch
	command.sprint = held.sprint
	command.aim = held.aim
	command.yaw = self._yaw
	command.pitch = self._pitch

	local fields: { [string]: any } = command.fields
	fields.slot = EMPTY_HANDS

	if fields.shots == nil then
		fields.shots = {}
	end
end

--[[
    This frame's base yaw and pitch, radians, and the head offset, which
    stays level. It makes nothing
--]]

function Input.look(self: Self): (number, number, number, number)
	return self._yaw, self._pitch, LEVEL, LEVEL
end

function Input._began(self: Self, input: InputObject, processed: boolean)
	if processed then
		return
	end

	if input.UserInputType == Enum.UserInputType.Touch then
		self:_touched(input)
		return
	end

	self:press(input.KeyCode.Name, true)
	self:press(input.UserInputType.Name, true)
end

function Input._changed(self: Self, input: InputObject)
	if input.UserInputType == Enum.UserInputType.MouseMovement then
		local delta: Vector3 = input.Delta
		self:turn(delta.X, delta.Y, MOUSE_TURN)
	elseif input == self._drag then
		local at: Vector3 = input.Position
		self:turn(at.X - self._dragged.X, at.Y - self._dragged.Y, TOUCH_TURN)
		self._dragged = at
	elseif input == self._stick then
		self:_move(input.Position)
	end
end

function Input._ended(self: Self, input: InputObject)
	if input == self._stick then
		self._stick = nil
		self:stick(0, 0)
		self:_show(false)
	elseif input == self._drag then
		self._drag = nil
	elseif input == self._jump then
		self._jump = nil
		self._held.jump = false
	else
		self:press(input.KeyCode.Name, false)
		self:press(input.UserInputType.Name, false)
	end
end

--[[
    Takes a touch that no button took: on the screen's left side it drives
    the stick from where it began, and on the right it drags the look, one
    touch each at a time
--]]

function Input._touched(self: Self, input: InputObject)
	local at: Vector3 = input.Position
	local camera: Camera = Workspace.CurrentCamera

	if at.X < camera.ViewportSize.X * STICK_SIDE then
		if self._stick == nil then
			self._stick = input
			self._origin = at
			self:_show(true)
			self:_move(at)
		end
	elseif self._drag == nil then
		self._drag = input
		self._dragged = at
	end
end

-- The stick's axes from its touch's place, and its thumb drawn there, held to the ring
function Input._move(self: Self, at: Vector3)
	local origin: Vector3 = self._origin
	self:stick((at.X - origin.X) / STICK_RADIUS, (origin.Y - at.Y) / STICK_RADIUS)

	local thumb: Frame? = self._thumb
	if thumb then
		local x: number = origin.X + self._right * STICK_RADIUS
		local y: number = origin.Y - self._forward * STICK_RADIUS
		thumb.Position = UDim2.fromOffset(x, y)
	end
end

-- Shows the stick's ring and thumb where its touch began, or hides them
function Input._show(self: Self, shown: boolean)
	local ring: Frame? = self._ring
	local thumb: Frame? = self._thumb
	if not ring or not thumb then
		return
	end

	ring.Position = UDim2.fromOffset(self._origin.X, self._origin.Y)
	ring.Visible = shown
	thumb.Visible = shown
end

-- A circle of a diameter in pixels, for the stick's ring and thumb, hidden until a touch drives the stick
local function circle(diameter: number, parent: ScreenGui): Frame
	local frame: Frame = Instance.new("Frame")
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Size = UDim2.fromOffset(diameter, diameter)
	frame.BackgroundTransparency = 0.5
	frame.Visible = false
	frame.Parent = parent

	local corner: UICorner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = frame

	return frame
end

--[[
    Puts up the touch controls: the stick's ring and thumb, hidden until a
    touch drives the stick, and the jump button in the bottom right corner,
    whose touch holds the jump until it lifts wherever it has moved to
--]]

function Input._controls(self: Self)
	-- Boot-time wait: the PlayerGui may not have arrived when the client's scripts start
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui", GUI_WAIT) :: PlayerGui?
	if not playerGui then
		error(`The touch controls found no PlayerGui within {GUI_WAIT} s`)
	end

	local screen: ScreenGui = Instance.new("ScreenGui")
	screen.Name = "DevControls"
	screen.ResetOnSpawn = false
	screen.Parent = playerGui

	self._ring = circle(RING, screen)
	self._thumb = circle(THUMB, screen)

	local button: TextButton = Instance.new("TextButton")
	button.Name = "Jump"
	button.Text = "Jump"
	button.AnchorPoint = Vector2.new(1, 1)
	button.Position = UDim2.new(1, -JUMP_MARGIN, 1, -JUMP_MARGIN)
	button.Size = UDim2.fromOffset(JUMP_SIZE, JUMP_SIZE)
	button.BackgroundTransparency = 0.5
	button.Parent = screen

	-- Lives for the client session, as the button does; the touch's end reaches _ended through UserInputService
	button.InputBegan:Connect(function (input: InputObject)
		if input.UserInputType == Enum.UserInputType.Touch and self._jump == nil then
			self._jump = input
			self._held.jump = true
		end
	end)
end

type Self = typeof(setmetatable({} :: Fields, Input))

return Input
