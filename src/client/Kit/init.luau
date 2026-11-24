--!strict
-- A small declarative UI kit. Components are plain functions that return element trees; `Kit.update` diffs a new
-- tree against the mounted one and touches only the properties and children that changed.
--
-- Elements are plain tables, so the same component code runs under Lune, where tools/render.luau turns the tree
-- into JSON for the CI screenshots, with no Roblox instance involved.

local Kit = {}

export type Element = {
	class: string,
	props: { [string]: any },
	children: { [any]: any }?,
}

-- Event props start with "on": onActivated → Activated, onMouseEnter → MouseEnter, …
local function eventName(key: string): string?
	if string.sub(key, 1, 2) == "on" and #key > 2 then
		return string.sub(key, 3)
	end
	return nil
end

function Kit.e(class: string, props: { [string]: any }?, children: { [any]: any }?): Element
	return { class = class, props = props or {}, children = children }
end

-- Wraps an expensive subtree: while `key` stays the same the previous element table is reused, and the diff skips
-- the whole subtree because old and new are the same table.
local memo: { [string]: { key: string, element: Element } } = {}
function Kit.memo(slot: string, key: string, build: () -> Element): Element
	local cached = memo[slot]
	if cached and cached.key == key then
		return cached.element
	end
	local element = build()
	memo[slot] = { key = key, element = element }
	return element
end

-- Mounting (Roblox only) ----------------------------------------------------------------------------------------------

type Node = {
	key: any,
	element: Element,
	instance: Instance,
	handlers: { [string]: any },
	connections: { [string]: RBXScriptConnection },
	children: { [any]: Node },
}

local function childName(key: any): string
	return if type(key) == "number" then string.format("%04d", key) else tostring(key)
end

local function applyProps(node: Node, old: { [string]: any }?, new: { [string]: any })
	local instance = node.instance :: any
	for key, value in new do
		if key == "ref" then
			continue
		end
		local event = eventName(key)
		if event then
			node.handlers[event] = value
			if not node.connections[event] then
				node.connections[event] = (instance[event] :: RBXScriptSignal):Connect(function(...)
					local handler = node.handlers[event]
					if handler then
						handler(...)
					end
				end)
			end
		elseif old == nil or old[key] ~= value then
			instance[key] = value
		end
	end
end

local mountNode: (Element, Instance, any) -> Node

local function reconcileChildren(node: Node, children: { [any]: any }?)
	local seen = {}
	if children then
		for key, child in children do
			if child then
				seen[key] = true
				local existing = node.children[key]
				if existing and existing.element.class == child.class then
					Kit.reconcile(existing, child)
				else
					if existing then
						existing.instance:Destroy()
					end
					node.children[key] = mountNode(child, node.instance, key)
				end
			end
		end
	end
	for key, existing in node.children do
		if not seen[key] then
			existing.instance:Destroy()
			node.children[key] = nil
		end
	end
end

mountNode = function(element: Element, parent: Instance, key: any): Node
	local instance = Instance.new(element.class :: any)
	instance.Name = childName(key)
	local node: Node =
		{ key = key, element = element, instance = instance, handlers = {}, connections = {}, children = {} }
	if type(key) == "number" and instance:IsA("GuiObject") and element.props.LayoutOrder == nil then
		(instance :: GuiObject).LayoutOrder = key
	end
	applyProps(node, nil, element.props)
	reconcileChildren(node, element.children)
	instance.Parent = parent
	local ref = element.props.ref
	if ref then
		ref(instance)
	end
	return node
end

function Kit.reconcile(node: Node, element: Element)
	local old = node.element
	if old == element then
		return
	end
	-- A property that disappears has no "unset" in Roblox, so the instance is rebuilt instead.
	for key in old.props do
		if element.props[key] == nil and not eventName(key) and key ~= "ref" then
			local parent = node.instance.Parent
			node.instance:Destroy()
			local fresh = mountNode(element, parent :: Instance, node.key)
			node.instance = fresh.instance
			node.handlers = fresh.handlers
			node.connections = fresh.connections
			node.children = fresh.children
			node.element = element
			return
		end
	end
	applyProps(node, old.props, element.props)
	node.element = element
	reconcileChildren(node, element.children)
end

export type Handle = { root: Node }

function Kit.mount(element: Element, parent: Instance, name: string): Handle
	return { root = mountNode(element, parent, name) }
end

function Kit.update(handle: Handle, element: Element)
	if handle.root.element.class ~= element.class then
		local parent = handle.root.instance.Parent :: Instance
		local key = handle.root.key
		handle.root.instance:Destroy()
		handle.root = mountNode(element, parent, key)
	else
		Kit.reconcile(handle.root, element)
	end
end

return Kit
