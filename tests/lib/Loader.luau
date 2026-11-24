-- Loads the game's modules under Lune exactly as Rojo lays them out in Roblox: `script`, `script.Parent.X`,
-- `:WaitForChild` and `require(instance)` work on the file tree, so the tests run the real code, unchanged.

local fs = require("@lune/fs")
local luau = require("@lune/luau")

local Loader = {}

local nodes: { [string]: any } = {}
local modules: { [string]: any } = {}
local loading: { [string]: boolean } = {}
local extraGlobals: { [string]: any } = {}

local Node = {}

local function dirname(path: string): string
	return string.match(path, "^(.*)/[^/]+$") or ""
end

local function basename(path: string): string
	return string.match(path, "([^/]+)$") or path
end

-- A node is either a folder, a module file, or a folder with an init module (which is a module with children).
local function makeNode(path: string, file: string?, isDir: boolean): any
	local existing = nodes[path]
	if existing then
		return existing
	end
	local node = setmetatable({ __path = path, __file = file, __isDir = isDir }, Node)
	nodes[path] = node
	return node
end

local function childOf(node: any, name: string): any
	if not node.__isDir then
		return nil
	end
	local dir = node.__path
	for _, ext in { ".luau", ".lua" } do
		local file = dir .. "/" .. name .. ext
		if fs.isFile(file) then
			return makeNode(dir .. "/" .. name, file, false)
		end
	end
	local sub = dir .. "/" .. name
	if fs.isDir(sub) then
		for _, init in { "init.luau", "init.lua" } do
			if fs.isFile(sub .. "/" .. init) then
				return makeNode(sub, sub .. "/" .. init, true)
			end
		end
		return makeNode(sub, nil, true)
	end
	return nil
end

local function parentOf(node: any): any
	local parent = dirname(node.__path)
	if parent == "" or parent == "." then
		return nil
	end
	for _, init in { "init.luau", "init.lua" } do
		if fs.isFile(parent .. "/" .. init) then
			return makeNode(parent, parent .. "/" .. init, true)
		end
	end
	return makeNode(parent, nil, true)
end

Node.__index = function(node: any, key: string): any
	if key == "Parent" then
		return parentOf(node)
	elseif key == "Name" then
		return basename(node.__path)
	elseif key == "WaitForChild" or key == "FindFirstChild" then
		return function(self: any, name: string): any
			local child = childOf(self, name)
			if not child and key == "WaitForChild" then
				error("WaitForChild: no " .. name .. " in " .. self.__path, 2)
			end
			return child
		end
	elseif key == "IsA" then
		return function(_self: any, class: string): boolean
			return class == "ModuleScript" or class == "Folder" or class == "Instance"
		end
	end
	local child = childOf(node, key)
	if child == nil then
		error(key .. " is not a valid member of " .. node.__path, 2)
	end
	return child
end
Node.__tostring = function(node: any): string
	return node.__path
end

local baseEnv = {
	assert = assert,
	error = error,
	getmetatable = getmetatable,
	ipairs = ipairs,
	next = next,
	pairs = pairs,
	pcall = pcall,
	print = print,
	rawequal = rawequal,
	rawget = rawget,
	rawlen = rawlen,
	rawset = rawset,
	select = select,
	setmetatable = setmetatable,
	tonumber = tonumber,
	tostring = tostring,
	type = type,
	typeof = typeof,
	unpack = table.unpack,
	xpcall = xpcall,
	warn = print,
	bit32 = bit32,
	buffer = buffer,
	coroutine = coroutine,
	math = math,
	os = os,
	string = string,
	table = table,
	utf8 = utf8,
}

local function requireNode(node: any): any
	if type(node) ~= "table" or getmetatable(node) ~= Node then
		error("require expects a module instance, got " .. tostring(node), 2)
	end
	local file = node.__file
	if not file then
		error("not a module: " .. node.__path, 2)
	end
	if modules[file] ~= nil then
		return modules[file]
	end
	if loading[file] then
		error("circular require of " .. file, 2)
	end
	loading[file] = true
	local env = setmetatable({}, {
		__index = function(_, key)
			if key == "script" then
				return node
			elseif key == "require" then
				return requireNode
			end
			local extra = extraGlobals[key]
			if extra ~= nil then
				return extra
			end
			return baseEnv[key]
		end,
	})
	local chunk = luau.load(fs.readFile(file), {
		debugName = file,
		environment = env,
		injectGlobals = false,
	})
	local result = chunk()
	loading[file] = nil
	modules[file] = result
	return result
end

-- Adds globals the loaded modules can see (the UI renderer adds Roblox datatype stand-ins).
function Loader.setGlobals(globals: { [string]: any })
	for k, v in globals do
		extraGlobals[k] = v
	end
end

-- The node (stand-in instance) for a folder or module path.
function Loader.node(path: string): any
	local node = nodes[path]
	if node then
		return node
	end
	local parent = makeNode(dirname(path), nil, true)
	return childOf(parent, basename(path)) or error("nothing at " .. path)
end

-- Loader.load("src/shared/Rules/World") → that module's return value.
function Loader.load(path: string): any
	local node = nodes[path]
	if not node then
		local parent = makeNode(dirname(path), nil, true)
		node = childOf(parent, basename(path))
		if not node then
			error("no module at " .. path)
		end
	end
	return requireNode(node)
end

return Loader
