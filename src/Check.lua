local check = {}

function check.isDescendant(state1, state2)
	if not state2 then
		return function(item, index)
			return check.isDescendant(item, state1)
		end
	end

	local parent = state1.parent

	while parent do
		if parent == state2 then
			return true
		end
		parent = parent.parent
	end

	return false
end

function check.isAtomic(state)
	return state.type == "atomic"
end
function check.isCompound(state)
	return state.type == "compound"
end
function check.isHistory(state)
	return state.type == "history"
end
function check.isParallel(state)
	return state.type == "parallel"
end

return check
