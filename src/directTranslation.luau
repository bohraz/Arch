local function exitInterpreter() end

local function microstep(enabledTransitions) end

local function executeTransitionContent(enabledTransitions) end

local function isInFinalState(s) end

local function getProperAncestors(state1, state2)
	local orderedAncestors = {}
	local parent = state1.parent

	repeat
		table.insert(orderedAncestors, parent)
		parent = parent.parent
	until not parent or parent == state2

	return orderedAncestors
end

local function isDescendant(state1, state2)
	local parent = state1.parent

	while parent do
		if parent == state2 then
			return true
		end
		parent = parent.parent
	end

	return false
end

local function findLCCA(stateList)
	local properAncestorList = {}

	-- Populate the list of proper ancestors for each state
	for _, v in stateList do
		table.insert(properAncestorList, getProperAncestors(v))
	end

	-- Extract the head of properAncestorList
	local headOfProperAncestorList = table.remove(properAncestorList, 1)

	-- Iterate through the ancestors of the head
	for _, ancestor in headOfProperAncestorList do
		local isCommon = true

		-- Check if the ancestor is common across all lists
		for _, ancestorList in properAncestorList do
			if not table.find(ancestorList, ancestor) then
				isCommon = false
				break
			end
		end

		-- If the ancestor is common across all lists, return it
		if isCommon then
			return ancestor
		end
	end

	return -- If no common ancestor is found, return a default value (eventTransition.g., global ancestor)
end

local function getTransitionDomain(transition)
	return findLCCA({ transition.source, transition.target })
end

local function computeExitSet(enabledTransitions)
	local statesToExit = {}
	for i, t in enabledTransitions do
		if t.target then -- for targetless transitions only
			local child = getTransitionDomain(t) --initial point of exit is the LCCA of target and source
			while child do
				table.insert(statesToExit, 1, child) --ensures exit set is in ancestry order(from child to ancestor)
				child = child.current
			end
		end
	end
	return statesToExit
end

local function exitStates(enabledTransitions)
	local statesToExit = computeExitSet(enabledTransitions)

	for i, s in statesToExit do
		--assign history here in future
		s:OnExit()
	end
end

local function addDescendantStatesToEnter(state, statesToEnter, statesForDefaultEntry)
	table.insert(statesToEnter, state)
	if state.type == "compound" then
		table.insert(statesForDefaultEntry, state)
		addDescendantStatesToEnter(state.initial, statesToEnter, statesForDefaultEntry)
	end --elseif isParallelState
end

local function addAncestorStatesToEnter(state, ancestor, statesToEnter)
	for i, anc in getProperAncestors(state, ancestor) do
		table.insert(statesToEnter, anc)
		--if anc is a parallel state then fill descendants as well
	end
end

local function computeEntrySet(transitions, statesToEnter, statesForDefaultEntry)
	for i, t in transitions do
		local ancestor = getTransitionDomain(t)
		addDescendantStatesToEnter(t.target, statesToEnter, statesForDefaultEntry)
		addAncestorStatesToEnter(t.target, ancestor, statesToEnter)
	end
end

local function enterStates(enabledTransitions, context)
	local statesToEnter = {}
	local statesForDefaultEntry = {}

	local defaultHistoryContent = {}

	computeEntrySet(enabledTransitions, statesToEnter, statesForDefaultEntry)
	for i, s in statesToEnter do
		s:OnEntry()
	end
end

local function isCancelEvent() end

-- I'm not sure how this function works exactly, reference scxml before changing
local function removeConflictingTransitions(enabledTransitions)
	local filteredTransitions = {}

	for i, transition in enabledTransitions do
		local t1Preempted = false
		local transitionsToRemove = {}

		local filteredExitSet = computeExitSet(filteredTransitions)

		for _, state in computeExitSet({ transition }) do
			if table.find(filteredExitSet, state) then
				if isDescendant(transition.source, state) then
					table.insert(transitionsToRemove, state)
				else
					t1Preempted = true
					break
				end
			end
		end

		if not t1Preempted then
			for _, toRemove in transitionsToRemove do
				table.remove(filteredTransitions, table.find(filteredTransitions, toRemove))
			end
			table.insert(filteredTransitions, transition)
		end
	end

	return filteredTransitions
end

local function passedGuards(transition)
	for i, guard in transition.guards or {} do
		if not guard() then
			return false
		end
	end
	return true
end

local function selectEventlessTransitions(configuration)
	local enabledTransitions = {}

	for i, state in configuration do -- loops through active states
		if state.type ~= "atomic" then -- skips loop if state is not atomic, ensuring ancestry order
			continue
		end

		local transition
		local stateToQuery = state
		while stateToQuery do -- finds first eventless transition, from child to ancestor, that passes guards
			local broken = false

			for _, eventlessTransition in stateToQuery.on._noevent do
				if passedGuards(eventlessTransition) then
					transition = eventlessTransition
					broken = true
					break
				end
			end

			if broken then
				break
			end

			stateToQuery = stateToQuery.parent
		end
		if transition then
			table.insert(enabledTransitions, transition)
		end
	end

	enabledTransitions = removeConflictingTransitions(enabledTransitions)

	return enabledTransitions
end

local function selectTransitions(event, configuration)
	local enabledTransitions = {}

	for i, state in configuration do -- loops through active states
		if state.type ~= "atomic" then -- skips loop if state is not atomic, because atomic states are the base of ancestry order
			continue
		end

		local transition
		local stateToQuery = state
		while stateToQuery do -- finds first transition, from child to ancestor, that passes guards
			local broken = false

			for _, eventTransition in stateToQuery.on[event.name] do
				if passedGuards(eventTransition) then
					transition = eventTransition
					broken = true
					break
				end
			end

			if broken then
				break
			end

			stateToQuery = stateToQuery.parent
		end
		if transition then
			table.insert(enabledTransitions, transition)
		end
	end

	enabledTransitions = removeConflictingTransitions(enabledTransitions)

	return enabledTransitions
end

local function mainEventLoop(machine)
	while machine.running do
		local enabledTransitions = {}
		local macrostepDone = false
		--here we handle eventless transitions and transitions handled by internal events until macrostep is complete
		while machine.running and not macrostepDone do
			enabledTransitions = selectEventlessTransitions()
			if #enabledTransitions == 0 then
				if #machine.internalQueue == 0 then
					macrostepDone = true
				else
					local internalEvent = machine.internalQueue[1]
					table.remove(machine.internalQueue, 1)
					machine._event = internalEvent
					enabledTransitions = selectTransitions(internalEvent)
				end
			end
			if not #enabledTransitions == 0 then
				microstep(enabledTransitions)
			end
		end
		if not machine.running then --either we're in a final state, and we break out of the loop
			break
		end
		--or we've completed a macrostep, so we start a new macrostep by waiting for an external event

		if #machine.internalQueue > 0 then
			continue
		end

		local externalEvent = machine.externalQueue[1]
		table.remove(machine.externalQueue, 1)
		if isCancelEvent(externalEvent) then
			machine.running = false
			continue
		end
		machine._event = externalEvent

		enabledTransitions = selectTransitions(externalEvent)
		if not #enabledTransitions == 0 then
			microstep(enabledTransitions)
		end
		task.wait()
	end
	--if we get here it means we have reached a top-level final state or have been cancelled
	exitInterpreter()
end

local function enterInitialStates(state, actions, context)
	repeat
		state = state[state.initial]
		if state.OnEntry then
			if typeof(state.OnEntry) == "function" then
				state.OnEntry(context)
			elseif typeof(state.OnEntry) == "string" then
				actions[state.OnEntry](context)
			end
		end
		state = state.substates
	until not state
end

local function initializeDatamodel(datamodel, actions, context)
	for name, state in datamodel do
		if state.OnInit then
			if typeof(state.OnInit) == "function" then
				state.OnInit(context)
			elseif typeof(state.OnInit) == "string" then
				actions[state.OnInit](context)
			end
		end
		if state.substates then
			initializeDatamodel(state.substates, actions, context)
		end
	end
end

-- Add parent property to every state and ensure it is correctly types.
local function buildDatamodel(parent, document)
	local states = {}

	for name, state in document do -- in this loop I should check to ensure the necessary properties exist
		if not state.id then
			error("State does not have id!")
		end

		states[name] = state
		states[name].parent = parent

		if state.substates then
			states[name].type = state.type or "compound"
			states[name].substates = buildDatamodel(parent, state.substates)
		else
			states[name].type = "atomic"
		end
	end

	return states
end

local machineList = {}
local interpreter = {}
interpreter.__index = interpreter -- do fun metamagic to make sure users cant access any methods except what i want them to

local function createMachine(document)
	--ensure document is correctly typed
	local machine = {}

	machine.id = document.id
	machine.initial = document.initial
	machine.context = {} -- make immutable
	machine.running = false

	machine.configuration = {} --current configuration of active states
	machine.statesToInvoke = {}
	machine.internalQueue = {}
	machine.externalQueue = {}
	machine.historyValue = {}

	machine.actions = document.actions
	machine.guards = document.guards

	machine.datamodel = buildDatamodel(machine, document.states)

	return setmetatable(machine, interpreter)
end

local function mapOptionsToMachine(machine) end

function interpreter:Start(options)
	if self.running then
		error("This machine is already running!")
	end

	mapOptionsToMachine(self)

	initializeDatamodel(self.datamodel, self.actions, self.context)

	self.running = true

	enterInitialStates(self.datamodel, self.actions, self.context)
	--mainEventLoop(self)
end

return createMachine
