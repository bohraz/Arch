local state = {}

state.id = "ChildB"

function state.OnExit(context, event, test)
	print(context, event)
end
state.events = {
	BackToA = "ChildA",
	after = {
		{ delay = 5, target = "ChildA", actions = {
			function()
				print("ACTION!")
			end,
		} },
	},
}

return state
