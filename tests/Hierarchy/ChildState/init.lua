local state = {}

state.id = "ChildA"
state.initial = "Grandchild"

state.events = {
	SwitchChild = {
		{ target = "ChildB" },
	},
}

return state
