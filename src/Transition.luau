local Sift = require(script.Parent.Parent.sift)
local Signal = require(script.Parent.Parent.signal)
local Promise = require(script.Parent.Parent.promise)
local Check = require(script.Parent.Check)

local function getProperAncestors(state1, state2)
	local orderedAncestors = {}
	local parent = state1.parent

	while parent do
		table.insert(orderedAncestors, parent)
		parent = parent.parent
	end

	return orderedAncestors
end

local function findLCCA(stateList) -- completed
	for _, anc in Sift.Array.filter(getProperAncestors(Sift.Array.first(stateList)), Check.isCompound) do
		local tail = Sift.Array.removeIndex(stateList, 1)
		if Sift.Array.every(tail, Check.isDescendant(anc)) then
			return anc
		end
	end
end

local function getTransitionDomain(transition)
	return findLCCA({ transition.target, transition.source })
end

--Finds the LCCA of each transition and adds each active child of the LCCA to the exit list in ancestry order.
local function computeExitSet(enabledTransitions)
	local statesToExit = {}
	for i, t in enabledTransitions do
		if t.target then -- for targetless transitions only
			local child = getTransitionDomain(t) --initial point of exit Check.is the LCCA of target and source
			while child.current do
				child = child.current
				table.insert(statesToExit, 1, child) --ensures exit set Check.is in ancestry order(from child to ancestor)
			end
		end
	end
	return statesToExit
end

local module = {}

function module.exitStates(enabledTransitions, machine, context, ...)
	local statesToExit = if not enabledTransitions then machine.configuration else computeExitSet(enabledTransitions)

	for i, s in statesToExit do
		if machine.debugMode then
			print("Exit: " .. s.id)
		end

		if s.parent then
			s.parent.historyState = s
		end

		if s.OnExit then
			s.OnExit(context, ...)
		end

		if s.threads and #s.threads > 0 then
			while #s.threads > 0 do
				local thread = table.remove(s.threads, 1)
				if coroutine.status(thread) == "normal" or coroutine.status(thread) == "running" then
					coroutine.yield(thread)
				end
				coroutine.close(thread)
			end
		end

		if s.janitor then
			s.janitor:Cleanup()
		end

		table.remove(machine.configuration, table.find(machine.configuration, s))
		s.active = false
		if s.parent then
			s.parent.current = nil
		end
	end

	return statesToExit
end

local function hasIntersection(t1, t2)
	return Sift.Array.some(computeExitSet({ t1 }), function(value, index, array)
		return Sift.Array.includes(t2, value)
	end)
end

local function removeConflictingTransitions(enabledTransitions) -- completed
	local filteredTransitions = {}

	for _, t1 in enabledTransitions do
		local t1Preempted = false
		local transitionsToRemove = {}

		for _, t2 in filteredTransitions do
			if hasIntersection(t1, t2) then
				if Check.isDescendant(t1.source, t2.source) then
					table.insert(transitionsToRemove, t2)
				else
					t1Preempted = true
					break
				end
			end
		end
		if not t1Preempted then
			for _, t3 in transitionsToRemove do
				filteredTransitions = Sift.Array.removeValue(filteredTransitions, t3)
			end
			table.insert(filteredTransitions, t1)
		end
	end

	return filteredTransitions
end

local function addDescendantStatesToEnter(state, statesToEnter, deepHistory) -- completed
	if state.history then
		addDescendantStatesToEnter(
			state.historyState or state.initial,
			statesToEnter,
			deepHistory or state.history == "deep"
		)
	else
		if Check.isCompound(state) then
			addDescendantStatesToEnter(
				if deepHistory then state.historyState or state.initial else state.initial,
				statesToEnter,
				deepHistory
			)
		elseif Check.isParallel(state) then
			for _, child in state.states do
				if not Sift.Array.some(statesToEnter, Check.isDescendant(child)) then
					addDescendantStatesToEnter(child, statesToEnter)
				end
			end
		end
	end
	table.insert(statesToEnter, 1, state)
end

local function addAncestorStatesToEnter(state, ancestor, statesToEnter) -- completed
	for i, anc in getProperAncestors(state, ancestor) do
		if not anc.parent or anc == ancestor then
			break -- test does this change functionality?
		end
		table.insert(statesToEnter, 1, anc)
		if Check.isParallel(anc) then
			for _, child in anc.states do
				if not Sift.Array.some(statesToEnter, Check.isDescendant(child)) then
					addDescendantStatesToEnter(child, statesToEnter)
				end
			end
		end
		--if anc Check.is a parallel state then fill descendants as well
	end
end

local function computeEntrySet(transitions)
	local statesToEnter = {}
	for i, t in transitions do
		if t.target then
			local ancestor = getTransitionDomain(t)
			addDescendantStatesToEnter(t.target, statesToEnter)
			addAncestorStatesToEnter(t.target, ancestor, statesToEnter)
		end
	end
	return statesToEnter
end

local function checkForAfter(state, machine)
	if not state.events or not state.events.after then
		return
	end

	local startTime = machine.logTime and workspace:GetServerTimeNow()

	for i, transition in state.events.after do
		local thread = task.delay(transition.delay, function()
			machine:Send("after", transition.delay, startTime)
		end)

		table.insert(state.threads, thread)
	end
end

function executeTransitionContent(enabledTransitions, machine, context, ...)
	for i, t in enabledTransitions do
		for _, action in t.actions or {} do
			context.janitor = if t.target then t.target.janitor else nil
			action(context, ...)
		end
	end
end

local function passedGuards(transition, machine, context, ...)
	for i, guard in transition.guards or {} do
		if not guard(context, ...) then
			return false
		end
	end
	return true
end

function module.enterStates(enabledTransitions, machine, context, ...)
	local statesForDefaultEntry = {}

	local defaultHistoryContent = {}

	local statesToEnter = computeEntrySet(enabledTransitions)
	for i, s in statesToEnter do
		if machine.debugMode then
			print("Enter: " .. s.id)
		end

		if s.janitor then
			context.janitor = s.janitor
		end

		context.target = s.id

		if s.OnEntry then
			s.OnEntry(context, ...)
		end

		context.target = nil

		if s.parent and not Check.isParallel(s.parent) then
			s.parent.current = s
		end

		s.active = true
		checkForAfter(s, machine)

		table.insert(machine.configuration, 1, s)
	end

	return statesToEnter
end

function module.selectTransitions(machine, context) --completed
	local enabledTransitions = {}

	local event = context.event
	local atomicStates = Sift.Array.filter(machine.configuration, Check.isAtomic)

	for _, state in atomicStates do
		for _, s in Sift.Array.insert(getProperAncestors(state), 1, state) do
			local breakLoop = false
			for _, transition in if s.events then s.events[event] or {} else {} do
				if passedGuards(transition, machine, context) then
					table.insert(enabledTransitions, transition)
					breakLoop = true
					break
				end
			end
			if breakLoop then
				break
			end
		end
	end

	enabledTransitions = removeConflictingTransitions(enabledTransitions)
	return enabledTransitions
end

function module.microstep(enabledTransitions, machine, context)
	local timeBegan = machine.logTime and workspace:GetServerTimeNow()

	local statesExited = module.exitStates(enabledTransitions, machine, context, table.unpack(machine._args))
	executeTransitionContent(enabledTransitions, machine, context, table.unpack(machine._args))
	local statesEntered = module.enterStates(enabledTransitions, machine, context, table.unpack(machine._args))

	local timeEnded = machine.logTime and workspace:GetServerTimeNow()

	local log = {
		statesEntered = statesEntered,
		statesExited = statesExited,
		transitions = enabledTransitions,
		context = context,
		timeBegan = timeBegan,
		timeEnded = timeEnded,
	}

	table.insert(machine.log, 1, log)

	if #machine.log > machine.maxLogs then
		repeat
			table.remove(machine.log, #machine.log)
		until #machine.log <= machine.maxLogs
	end
end

return module
