local ContextActionService = game:GetService("ContextActionService")
local Sift = require(script.Parent.sift)
local Signal = require(script.Parent.signal)
local Promise = require(script.Parent.promise)
local Janitor = require(script.Parent.janitor)
local Transition = require(script.Transition)
local Check = require(script.Check)

local function createContext(machine, context)
	context.Promise = Promise
	context.Sift = Sift
	function context.Send(eventName, ...)
		machine:Send(eventName, ...)
	end

	return context
end

local function mainEventLoop(machine)
	while machine._running do
		local enabledTransitions = {}
		local macrostepDone = false

		while machine._running and not macrostepDone do
			if #machine._queue > 0 then
				local event = table.remove(machine._queue, 1)
				machine._context.event = event.name
				machine._args = event.args

				enabledTransitions = Transition.selectTransitions(machine, machine._context)
			else
				macrostepDone = true
				continue
			end

			if #enabledTransitions > 0 then
				Transition.microstep(enabledTransitions, machine, machine._context)
			end
		end

		machine.EventAdded:Wait()
	end
end

local function transitionIsString(transition, events, event, state)
	events[event] = {
		{
			source = state.id,
			target = transition,
			guards = {},
			actions = {},
		},
	}
end

local function transitionIsTable(transition, events, event, state, datamodel, created)
	if not created then
		created = true
		events[event] = {}
	end
	if typeof(transition[1]) == "table" then
		events[event] = {}
		for _, t in transition do
			transitionIsTable(t, events, event, state, datamodel, true)
		end
	else
		if datamodel and transition.target then
			error("Top-Level transitions can not have a target!")
		end
		transition.guards = transition.guards or {}
		transition.actions = transition.actions or {}
		transition.source = state.id
		transition.event = event
		table.insert(events[event], transition)
	end
end

local function translateTransitions(events, state)
	for event, transition in events do
		if typeof(transition) == "string" then
			transitionIsString(transition, events, event, state)
		elseif typeof(transition) == "table" then
			transitionIsTable(transition, events, event, state)
		end

		if event == "after" then
			for _, delayedT in transition do
				table.insert(delayedT.guards, "after")
			end
		end
	end
end

local function translateDefinition(parent, substates, stateList)
	local states = {}

	if substates.states then
		local datamodel = substates

		datamodel.id = datamodel.id

		datamodel.active = false

		if datamodel.events then
			for event, transitionList in datamodel.events do
				if typeof(transitionList) == "string" then
					error("Top-Level transitions can not be strings!")
				elseif typeof(transitionList) == "table" then
					transitionIsTable(transitionList, datamodel.events, event, datamodel)
				end
			end
		end

		datamodel.states = translateDefinition(datamodel, datamodel.states, stateList)
		datamodel.type = if datamodel.parallel then "parallel" else "compound"

		states = datamodel
		stateList[datamodel.id] = datamodel
	else
		for name, childState in substates do -- in this loop I should check to ensure the necessary properties exist
			childState.id = childState.id or name

			if stateList[childState.id] then
				error("The id " .. childState.id .. " already exists, every id must be unique!")
			end

			childState.active = false
			childState.parent = parent

			local events = childState.events

			if events then
				translateTransitions(events, childState)
			end

			if childState.states then
				childState.type = if childState.parallel then "parallel" else "compound"
				childState.states = translateDefinition(childState, childState.states, stateList)
			else
				childState.type = "atomic"
			end

			states[childState.id or name] = childState
			stateList[childState.id or name] = childState
		end
	end

	return states
end

local function createDefinitionFromHierarchy(file)
	if not typeof(file) == "Instance" or not file:IsA("ModuleScript") then
		error("File must be a ModuleScript!")
	end
	local state = require(file)

	local fileChildren = file:GetChildren()
	if #fileChildren > 0 then
		for _, child in fileChildren do
			if child:IsA("ModuleScript") then
				if not state.states then
					state.states = {}
				end

				local s = createDefinitionFromHierarchy(child)
				if not s.omit then
					state.states[child.Name] = s
				end
			end
		end
	end

	return state
end

local function addReferences(state, actions, guards, stateList)
	if Check.isCompound(state) or Check.isHistory(state) then
		if not state.initial then
			error("Compound states must have an initial state property!")
		end
		if not state.states[state.initial] then
			error("Initial state " .. state.initial .. " does not exist!")
		end
		state.initial = state.states[state.initial]
	end

	if state.events then
		for event, transitionList in state.events do
			for _, transition in transitionList do
				transition.source = state
				transition.target = if transition.target
					then state.parent.states[transition.target] or stateList[transition.target]
					else nil

				if transition.guards then
					for i, guard in transition.guards do
						if typeof(guard) == "string" then
							if not guards[guard] then
								error(guard .. " does not exist in the guards table!")
							end
							transition.guards[i] = guards[guard]
						end
					end
				end

				if transition.actions then
					for i, action in transition.actions do
						if typeof(action) == "string" then
							if not actions[action] then
								error(action .. " does not exist in the actions table!")
							end
							transition.actions[i] = actions[action]
						end
					end
				end
			end
		end
	end

	if state.OnInit and typeof(state.OnInit) == "string" then
		if not actions[state.OnInit] then
			error("OnInit does not exist in the actions table!")
		end
		state.OnInit = actions[state.OnInit]
	end
	if state.OnEntry and typeof(state.OnEntry) == "string" then
		if not actions[state.OnEntry] then
			error("OnEntry does not exist in the actions table!")
		end
		state.OnEntry = actions[state.OnEntry]
	end
	if state.OnExit and typeof(state.OnExit) == "string" then
		if not actions[state.OnExit] then
			error("OnExit does not exist in the actions table!")
		end
		state.OnExit = actions[state.OnExit]
	end
	if state.janitor then
		state.janitor = Janitor.new()
	end

	for _, s in state.states or {} do
		addReferences(s, actions, guards, stateList)
	end
end

local function buildDatamodel(definition, stateList, machine)
	local datamodel = {}

	datamodel.id = definition.id
	datamodel.initial = definition.initial
	datamodel.active = false

	definition.actions = definition.actions or {}
	definition.guards = definition.guards or {}

	definition.guards["after"] = function(context, eventName, transition, startTime)
		local currentTime = if machine.logType == "workspace" then workspace:GetServerTimeNow() else os.clock()

		return currentTime - startTime >= transition.delay
	end

	datamodel = translateDefinition(nil, definition, stateList)
	addReferences(datamodel, machine._actions, machine._guards, stateList)

	return datamodel
end

local function initializeDatamodel(datamodel, machine)
	for name, state in datamodel.states do
		if state.OnInit then
			state.OnInit(machine.context)
		end
		if machine.debugMode then
			print("Init: " .. state.id)
		end
		if state.states then
			initializeDatamodel(state, machine)
		end
	end
end

local baseMachine = {}
baseMachine.__index = baseMachine

local function buildMachine(definition, options)
	local machine = {}
	options = options or {}

	machine._context = createContext(machine, options.context or {})

	machine._running = false

	machine.configuration = {} -- set
	machine._queue = {} -- array
	machine._stateList = {} -- array

	machine.log = {} -- array

	machine._actions = options.actions or {} -- dictionary
	machine._guards = options.guards or {} -- dictionary

	machine.EventAdded = Signal.new()

	machine.maxLogs = options.maxLogs or 30
	machine.logType = options.logType or "default"

	machine.debugMode = options.debugMode or false

	if typeof(definition) == "Instance" and definition:IsA("ModuleScript") then
		definition = createDefinitionFromHierarchy(definition)
	end

	machine.datamodel = buildDatamodel(definition, machine._stateList, machine)

	return setmetatable(machine, baseMachine)
end

function baseMachine:Start()
	if self._running then
		warn("This machine is already running!")
		return
	end

	initializeDatamodel(self.datamodel, self)

	self._running = true
	self.datamodel.active = true

	Transition.enterStates({ { target = self.datamodel } }, self, self._context)
	task.spawn(mainEventLoop, self)
end

function baseMachine:Send(eventName, ...)
	if not self._running then
		warn("This machine is not running yet, make sure to Start the machine before sending events!")
		return
	end

	table.insert(self._queue, { name = eventName, args = { ... } })
	self.EventAdded:Fire()
end

return {
	createMachine = buildMachine,
}
