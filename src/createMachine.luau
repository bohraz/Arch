local RunService = game:GetService("RunService")

local jecs = require(script.Parent.Parent.jecs)
local janitor = require(script.Parent.Parent.janitor)
local signal = require(script.Parent.Parent.signal)

type ContextConfig = {
	[string]: any,
}

type Context = {
	event: string?,
	source: string?,
	target: string?,

	read send: (string, ...any) -> nil,

	[string]: any,

	janitor: janitor.Janitor?,
	read world: jecs.World?,
	read entity: jecs.Entity?,
}

type MachineSymbol = string | number
type ActionFn = (context: Context, ...any) -> nil
type GuardFn = (context: Context, ...any) -> boolean

type Transition = {
	read target: string?,

	read actions: { ActionFn }?,
	read guards: { GuardFn }?,
}

type AtomicState = {
	read type: "atomic" | "final",

	name: string?,
	parent: string?,
	active: boolean?,
	janitor: boolean?,

	read entry: ActionFn?,
	read exit: ActionFn?,
	read components: { jecs.Entity }?,

	read on: { [string]: { Transition } }?,
}

type CompoundState = {
	read type: "compound" | "history" | "parallel",
	initial: string,

	name: string?,
	parent: string?,
	active: boolean?,
	janitor: boolean?,

	read entry: ActionFn?,
	read exit: ActionFn?,
	read components: { jecs.Entity }?,

	read on: { [string]: { Transition } }?,

	read states: States?,
}

type States = { [string]: CompoundState | AtomicState }

type MachineConfig = {
	read name: string,
	read world: jecs.World?,
	read machineComponent: jecs.Entity?,

	read ecs: {},

	read options: {
		read debugMode: boolean?,
		read log: boolean?,
		read maxLongs: number?,
	},

	read actions: { [string]: ActionFn }?,
	read context: ContextConfig?,
	read guards: { [string]: GuardFn }?,
	read components: { jecs.Entity }?,

	read initial: string,
	read states: States,
}

type MachineComponent = {
	value: MachineSymbol | { MachineSymbol },
	read events: { string },
	read context: Context,
	read janitors: { [string]: janitor.Janitor }?,
}

type Machine = {
	value: string, -- MachineSymbol
	read name: string,
	read component: jecs.Entity<MachineComponent>,
	read onTransition: signal.Signal<...any>,
	read system: () -> nil,
	read send: (jecs.Entity, string, ...any) -> nil | (string, ...any) -> nil,
	read start: (autoSetup: boolean?) -> nil,
	read stop: () -> nil,
}

local machine = {
	name = "TestMachine",
	world = {},

	context = {
		player = 0,
	},

	states = {
		initial = "StateA",
		StateA = {
			type = "compound",
			initial = "StateB",
			states = {
				StateB = {
					type = "atomic",
					entry = function(context: Context)
						print("Entering State B")
					end,
					exit = function(context: Context)
						print("Exiting State B")
					end,
				},
			},
		},
	},
}

local function interpretMachine(states: States): States
	local flattenedStates = {}
	local stack = { { parent = nil, states = states } }
	while #stack > 0 do
		local current = table.remove(stack, 1)
		if not current or not current.states then
			continue
		end

		if current.parent then
			current.parent.states = {}
		end

		for name, state in current.states do
			if current.parent then
				table.insert(current.parent.states, name)
			end

			state.name = name
			state.parent = if current.parent then current.parent.name else nil
			state.active = false

			flattenedStates[name] = state

			if state.states then
				table.insert(stack, {
					parent = state,
					states = state.states,
				})
			end
		end
	end

	return flattenedStates
end

local function createMachine(config: MachineConfig): Machine
	local _states = interpretMachine(config.states)

	-- ECS
	local world = config.world or jecs.World.new()
	local _component: jecs.Entity<MachineComponent> = config.machineComponent or world:component()
	local _changed: jecs.Entity<MachineComponent> = jecs.pair(_component, jecs.Rest)
	world:set(_component, jecs.Name, config.name)

	local function system()
		--Added
		for id, machine in world:query(_component):without(_changed) do
			--Compute initial entry set
			assert(_states[config.initial], "Initial state not found in states")
			local initialState: AtomicState | CompoundState = _states[config.initial]

			local value = {}
			local entrySet = { initialState }
			local stack = { initialState }

			while #stack > 0 do
				local nextState = table.remove(stack, 1)
				table.insert(entrySet, nextState)

				local stateType = nextState.type

				if stateType == "history" or stateType == "compound" then
					assert(nextState.initial, "Initial state not found in compound state")
					assert(table.find(nextState.states, nextState.initial), "Initial state not found in states")
					table.insert(stack, _states[nextState.initial])
				elseif stateType == "parallel" then
					for _, s in nextState.states do
						table.insert(stack, _states[s])
					end
				elseif stateType == "atomic" or stateType == "final" then
					table.insert(value, nextState.name)
				end
			end

			--Enter initial states
			for _, state in entrySet do
				for _, component in state.components or {} do
					world:set(component, _component, machine)
				end

				if state.entry then
					state.entry(state.context)
				end
				state.active = true
			end

			--Initialize machine component
			machine.value = value
			machine.events = if machine.events then machine.events else {}
			machine.context = if machine.context then machine.context else {}
			machine.janitors = {}

			for k, v in config.context do
				machine.context[k] = v
			end

			for name, state in _states do
				if state.janitor then
					machine.janitors[name] = janitor.new()
				end
			end

			world:set(id, _changed, machine)
		end

		--Removed
		for id, machine in world:query(_changed):without(_component) do
			if typeof(machine.value) ~= "table" then
				machine.value = { machine.value }
			end

			for _, name in machine.value do
				local state = _states[name]

				for _, component in state.components or {} do
					world:remove(component, _component)
				end

				if state.exit then
					state.exit(state.context)
				end

				if state.janitor then
					state.janitor:Cleanup()
					state.janitor:Destroy()
				end

				state.active = false
			end

			world:remove(id, _changed)
		end
		--Main Event Loop
		for id, state in world:query(_component) do
		end

		return nil
	end

	--Auto Scheduler
	local entity: jecs.Entity?
	local connection: RBXScriptConnection?
	local function start(autoSetup: boolean?)
		if connection then
			return nil
		end

		if autoSetup then
			assert(not entity, "Entity already exists")
			entity = world:entity()
			world:set(entity, _component, machine)
		end

		connection = RunService.Heartbeat:Connect(system)
		return nil
	end
	local function stop()
		if not connection then
			return nil
		end

		if entity then
			world:remove(entity, _component)
			entity = nil
		end

		connection:Disconnect()
		connection = nil
		return nil
	end
	local function send(entity: jecs.Entity, event: string, ...)
		assert(world:has(entity, _component), "Entity does not have a machine component")
		local machine = world:get(entity, _component) :: MachineComponent
		table.insert(machine.events, { event, ... })
		return nil
	end

	return {
		value = "",
		name = config.name,
		component = _component,
		system = system,
		start = start,
		stop = stop,
		send = send,
		onTransition = signal.new(),
	}
end

return createMachine
