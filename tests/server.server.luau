local createMachine = require(script.Parent.Packages.Arch.createMachine)

local config = {
	name = "TestMachine",

	context = {
		player = 0,
	},

	initial = "StateA",
	states = {
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

local machine = createMachine(config)

machine.start(true)
