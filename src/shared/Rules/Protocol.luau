--!strict
-- The orders a client may send and the exact shape of each. Anything else is dropped before a rule sees it: the
-- client is untrusted, and NaN, huge numbers or extra keys are common exploit inputs.

local Army = require(script.Parent.Army)

local Protocol = {}

Protocol.REMOTE_COMMAND = "KoR_Command"
Protocol.REMOTE_PUSH = "KoR_Push"

-- Field kinds: "string" (short id), "int", "troops", and a trailing "?" for optional.
Protocol.COMMANDS = {
	upgrade = { building = "string" },
	train = { troop = "string", count = "int" },
	research = { tech = "string" },
	finish = { job = "int" },
	heal = {},
	recruit = { hero = "string" },
	claimQuest = {},
	march = { kind = "string", x = "int", y = "int", troops = "troops?", hero = "string?" },
	recall = { march = "int" },
	relocate = { x = "int", y = "int" },
	guildCreate = { adj = "int", noun = "int" },
	guildJoin = { guild = "int" },
	guildLeave = {},
	guildHelp = {},
	readReports = {},
	-- Map chunks the client is looking at; the server pushes changes only for these.
	watch = { chunks = "ints" },
} :: { [string]: { [string]: string } }

Protocol.MARCH_KINDS = { gather = true, hunt = true, attack = true, scout = true }

local function isInt(v: any): boolean
	return type(v) == "number" and v == v and v % 1 == 0 and v >= -1e9 and v <= 1e9
end

local function isId(v: any): boolean
	return type(v) == "string" and #v > 0 and #v <= 32 and string.match(v, "^[%w_]+$") ~= nil
end

-- Returns a clean copy of the payload, or nil and the reason.
function Protocol.validate(name: any, payload: any): (any, string?)
	if type(name) ~= "string" then
		return nil, "bad command"
	end
	local schema = Protocol.COMMANDS[name]
	if not schema then
		return nil, "unknown command"
	end
	if payload == nil then
		payload = {}
	end
	if type(payload) ~= "table" then
		return nil, "bad payload"
	end
	for key in payload do
		if type(key) ~= "string" or schema[key] == nil then
			return nil, "unexpected field"
		end
	end
	local out = {}
	for key, kind in schema do
		local optional = string.sub(kind, -1) == "?"
		local base = if optional then string.sub(kind, 1, -2) else kind
		local value = payload[key]
		if value == nil then
			if not optional then
				return nil, "missing " .. key
			end
		elseif base == "string" then
			if not isId(value) then
				return nil, "bad " .. key
			end
			out[key] = value
		elseif base == "int" then
			if not isInt(value) then
				return nil, "bad " .. key
			end
			out[key] = value
		elseif base == "troops" then
			local troops = Army.sanitize(value)
			if not troops then
				return nil, "bad " .. key
			end
			out[key] = troops
		elseif base == "ints" then
			if type(value) ~= "table" or #value > 64 then
				return nil, "bad " .. key
			end
			local list = {}
			for i, v in value do
				if type(i) ~= "number" or not isInt(v) then
					return nil, "bad " .. key
				end
				table.insert(list, v)
			end
			out[key] = list
		end
	end
	return out, nil
end

return Protocol
