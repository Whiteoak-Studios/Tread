--[[
    Requiring Tread loads none of the server's modules and none of the
    client's, the server's handle loads none of the client's, and the
    client's handle none of the server's
--]]

--!strict
local Environment = require("../../Environment")

local GLOBALS: string = "tests/Fixtures/Environment/Globals.luau"
local CONSTANTS: string = "src/Constants.luau"
local CONSTANTS_PATH: string = "ReplicatedStorage.Packages.Tread.Constants"
local ROOT: string = "src/init.luau"
local SERVER: string = "src/Server/"
local CLIENT: string = "src/Client/"
local FIRST_CALLER: number = 2 -- The stack level of whatever read a constant, above the stand-in's own __index
local STACK_LIMIT: number = 200 -- Frames walked up from a read, past the deepest chain of requires

type Seen = { [string]: boolean }

--[[
    An environment whose Constants is a stand-in answering with the real
    values, which marks every file on the stack each time a module reads
    one. Nearly every module reads a constant as it loads, so a file that
    loads, or that requires one that does, is marked
--]]

local function watched(seen: Seen): any
	local constants: { [string]: any } = Environment.load(CONSTANTS)

	local standIn: any = setmetatable({}, {
		__index = function (_: any, key: string): any
			for level: number = FIRST_CALLER, STACK_LIMIT do
				local source: string? = debug.info(level, "s")
				if source == nil then
					break
				end

				seen[source] = true
			end

			return constants[key]
		end,
	})

	return Environment.load(GLOBALS, { [CONSTANTS_PATH] = standIn })
end

-- The first file marked whose name holds the text given, or nil for none
local function marked(seen: Seen, text: string): string?
	for source: string in seen do
		if string.find(source, text, 1, true) then
			return source
		end
	end

	return nil
end

return function (): (boolean, string | nil)
	-- A server's: Tread, then the server's handle
	local seen: Seen = {}
	local globals: any = watched(seen)
	local tread: any = globals.game:GetService("ReplicatedStorage").Packages.Tread
	local Tread: any = globals.require(tread)

	if type(Tread.startServer) ~= "function" or Tread.CODEC_VERSION == nil then
		return false, "Requiring Tread gave no entry points"
	elseif not marked(seen, ROOT) then
		return false, "The watch saw Tread's own file read no constant, so it sees nothing"
	elseif marked(seen, SERVER) or marked(seen, CLIENT) then
		return false, `Requiring Tread loaded {marked(seen, SERVER) or marked(seen, CLIENT)}`
	end

	globals.require(tread.Server)
	if not marked(seen, `{SERVER}init.luau`) then
		return false, "The watch never saw the server's handle load, so it can't tell what loads"
	elseif marked(seen, CLIENT) then
		return false, `The server's handle loaded {marked(seen, CLIENT)}`
	end

	-- A client's: Tread, then the client's handle
	seen = {}
	globals = watched(seen)
	tread = globals.game:GetService("ReplicatedStorage").Packages.Tread
	globals.require(tread)

	if marked(seen, SERVER) or marked(seen, CLIENT) then
		return false, `Requiring Tread on a client loaded {marked(seen, SERVER) or marked(seen, CLIENT)}`
	end

	globals.require(tread.Client)
	if not marked(seen, `{CLIENT}init.luau`) then
		return false, "The watch never saw the client's handle load, so it can't tell what loads"
	elseif marked(seen, SERVER) then
		return false, `The client's handle loaded {marked(seen, SERVER)}`
	end

	return true, nil
end
