--[[
    The dev game's stand-ins for Frontier Zero's loot, melee and building
    requests, each judged from the server's own cleared eye and refused when
    the client's claimed source lies away from it
--]]

--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Packages = ReplicatedStorage.Packages

local Tread = require(Packages.Tread)

local SOURCE: number = require(ServerScriptService.Server.Config.Fixtures).source
local LOOT_REACH: number = require(ServerScriptService.Server.Config.Fixtures).reach.loot
local SWING_REACH: number = require(ServerScriptService.Server.Config.Fixtures).reach.swing
local BUILD_REACH: number = require(ServerScriptService.Server.Config.Fixtures).reach.build

local Running: Tread.Server? = nil -- The server the fixtures were started on, which a build's overlap check asks

local Requests = {}

-- Starts the requests on the running server, once a server
function Requests.start(server: Tread.Server)
	if Running then
		error("Requests.start runs once a server, and it has already run", 2)
	end

	Running = server
end

--[[
    Whether a request may act at a point, judged from the server's cleared
    eye and never from the claim: refused as source when the client's
    claimed source lies past the leash from that eye, and as reach when the
    point lies past the reach from it
--]]

local function judge(character: Tread.Character, claimed: Vector3, at: Vector3, reach: number): (boolean, string | nil)
	local eye: Vector3 = character:getState().eye

	if (claimed - eye).Magnitude > SOURCE then
		return false, "source"
	elseif (at - eye).Magnitude > reach then
		return false, "reach"
	end

	return true, nil
end

-- A loot of what lies at a point, from the source the client claims, refused as source or reach
function Requests.loot(character: Tread.Character, claimed: Vector3, at: Vector3): (boolean, string | nil)
	return judge(character, claimed, at, LOOT_REACH)
end

-- A melee swing at a point, from the source the client claims, refused as source or reach
function Requests.swing(character: Tread.Character, claimed: Vector3, at: Vector3): (boolean, string | nil)
	return judge(character, claimed, at, SWING_REACH)
end

--[[
    A building piece placed at a CFrame with a size, from the source the
    client claims: refused as source or reach from the server's eye to the
    piece's center, and as overlap when the piece would overlap any live
    character's hull, the builder's own included
--]]

function Requests.build(
	character: Tread.Character,
	claimed: Vector3,
	at: CFrame,
	size: Vector3
): (boolean, string | nil)
	local server: Tread.Server? = Running
	if not server then
		error("Requests.build ran before Requests.start", 2)
	end

	local accepted: boolean, reason: string? = judge(character, claimed, at.Position, BUILD_REACH)
	if not accepted then
		return false, reason
	elseif server:overlaps(at, size) then
		return false, "overlap"
	end

	return true, nil
end

return Requests
