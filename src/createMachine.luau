--!strict

local jecs = require(script.Parent.Parent.jecs)
local janitor = require(script.Parent.Parent.janitor)

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
	janitor: janitor.Janitor | boolean?,

	read entry: ActionFn?,
	read exit: ActionFn?,
	read components: { jecs.Entity }?,

	read on: { [string]: { Transition } }?,
}

type CompoundState = {
	read type: "compound" | "history" | "parallel" | "final",
	initial: string,

	name: string?,
	parent: string?,
	active: boolean?,
	janitor: janitor.Janitor | boolean?,

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

	read states: { initial: string } & States,
}

type MachineComponent = {
	value: MachineSymbol,
	read events: { string },
	read context: Context,
}

type Machine = {
	value: MachineSymbol?,
	read name: string,
	read component: jecs.Entity<MachineComponent>,
	read onTransition: () -> nil, --signal
	read system: () -> nil,
	read start: () -> nil,
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
			state.janitor = if state.janitor == true then janitor.new() else state.janitor

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

local function createMachine(config: MachineConfig)
	local _states = interpretMachine(config.states)

	-- ECS
	local world = config.world or jecs.World.new()
	local _component: jecs.Entity<MachineComponent> = config.machineComponent or world:component()
	local _changed: jecs.Entity<MachineComponent> = jecs.pair(_component, jecs.Rest)
	world:set(_component, jecs.Name, config.name)

	local machine = {
		name = config.name,
		component = _component,
		system = function() end,
		start = function() end,
		stop = function() end,
	}

	return machine
end
