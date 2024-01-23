local TestEZ = require(script.Parent.Packages.testez)

return function()
	local arch = require(script.Parent.Packages.Arch)

	describe("a single-layer machine", function()
		local machine
		it("should be able to build and start", function()
			expect(function()
				machine = arch.createMachine({
					id = "basic fsm",
					initial = "StateA",

					states = {
						StateA = {
							id = "StateA",
							janitor = true,

							events = {
								Switch = "StateB",
								Switch2 = {
									{
										target = "StateB",
										guards = {
											function()
												return false
											end,
										},
									},
								},
								Switch3 = {
									target = "StateB",
									actions = {
										function() end,
									},
								},
							},
						},
						StateB = {
							id = "StateB",
							janitor = true,

							events = {
								Switch1 = {
									target = "StateA",
									guards = {
										"AlwaysTrueGuard",
									},
									actions = {
										function() end,
										"RandomStringAction",
									},
								},
								ToC = "StateC",
							},
						},
						StateC = {
							id = "StateC",

							OnEntry = function() end,
							OnExit = function() end,

							events = {
								refresh = "StateC",
								targetless = {
									actions = {
										function() end,
									},
								},
								ToB = {
									target = "StateB",
									actions = {
										function(context)
											context.janitor:Add(Instance.new("Part"), "Destroy")
										end,
									},
								},
							},
						},
					},
				}, {
					guards = {
						AlwaysTrueGuard = function()
							return true
						end,
					},
					actions = {
						RandomStringAction = function() end,
					},
				})
				machine:Start()
			end).never.to.throw()
		end)

		it("should subscribe to onTransition event", function()
			expect(function()
				machine.onTransition:Connect(function(stateOfTheMachine)
					--print(stateOfTheMachine, machine.configuration)
				end)
			end).never.to.throw()
		end)

		it("should be able to transition", function()
			expect(function()
				assert(machine.configuration[1].id == "StateA")
				machine:Send("Switch")
				assert(machine.configuration[1].id == "StateB")
				machine:Send("Switch1")
				assert(machine.configuration[1].id == "StateA")
				machine:Send("Switch2")
				assert(machine.configuration[1].id == "StateA")
				machine:Send("Switch3")
			end).never.to.throw()
		end)

		it("should be able to self-transition", function()
			expect(function()
				machine:Send("ToC")
				assert(machine.configuration[1].id == "StateC")
			end).never.to.throw()
			expect(function()
				machine:Send("refresh")
				assert(machine.configuration[1].id == "StateC")
			end).never.to.throw()
		end)

		it("should allow targetless transitions", function()
			expect(function()
				machine:Send("targetless")
				assert(machine.configuration[1].id == "StateC")
			end).never.to.throw()
		end)

		it("should give janitor to targeted transition actions", function()
			expect(function()
				machine:Send("ToB")
				assert(machine.configuration[1].id == "StateB")
			end).never.to.throw()
		end)

		it("should allow root-level parallellism", function()
			expect(function()
				local pMachine = arch.createMachine({
					id = "parallelMachine",
					parallel = true,

					states = {
						StateA = {},
						StateB = {},
					},
				})

				pMachine:Start()

				assert(pMachine.configuration[1].id == "StateA" or pMachine.configuration[1].id == "StateB")
				assert(pMachine.configuration[2].id == "StateA" or pMachine.configuration[2].id == "StateB")
			end).never.to.throw()
		end)
	end)
	describe("a multi-layer machine", function()
		local machine
		it("should be able to build and start", function()
			expect(function()
				machine = arch.createMachine({
					id = "multi-layer machine",
					initial = "ChildA",

					states = {
						ChildA = {
							initial = "GrandchildA",
							OnExit = function() end,
							OnDestroy = "destroyA",

							states = {
								GrandchildA = {},
								GrandhcildB = {},
							},

							events = {
								["CA-CB"] = {
									target = "ChildB",
								},
								["CA-CC"] = "ChildC",
								["CA-GGD"] = "Great-GrandchildD",
								["CA-GD"] = "GrandchildD",
							},
						},
						ChildB = {
							initial = "GrandchildC",
							history = "deep",

							OnDestroy = function(context) end,

							events = {
								["CB-CA"] = "ChildA",
							},

							states = {
								GrandchildC = {
									initial = "Great-GrandchildA",

									states = {
										["Great-GrandchildA"] = {
											events = {
												["GGA-GGB"] = "Great-GrandchildB",
											},
										},
										["Great-GrandchildB"] = {},
									},
								},
								GrandchildD = {
									initial = "Great-GrandchildC",
									history = "shallow",

									events = {
										["GD-GC"] = "GrandchildC",
									},

									states = {
										["Great-GrandchildC"] = {},
										["Great-GrandchildD"] = {},
									},
								},
							},
						},
						ChildC = {
							parallel = true,

							states = {
								GrandchildE = {},
								GrandchildF = {},
							},
						},
					},
				}, {
					context = {},
					actions = {
						destroyA = function() end,
					},
				})
				machine:Start()
			end).never.to.throw()
		end)

		it("should do basic transitions", function()
			expect(function()
				machine:Send("CA-CB")
				assert(machine.configuration[1].id == "Great-GrandchildA")
				machine:Send("GGA-GGB")
				assert(machine.configuration[1].id == "Great-GrandchildB")
				machine:Send("CB-CA")
				assert(machine.configuration[1].id == "GrandchildA")
			end).never.to.throw()
		end)

		it("should allow history states", function()
			expect(function()
				machine:Send("CA-CB")
				assert(machine.configuration[1].id == "Great-GrandchildB")
				machine:Send("CB-CA")
			end).never.to.throw()

			expect(function()
				machine:Send("CA-GGD")
				assert(machine.configuration[1].id == "Great-GrandchildD")
				machine:Send("GD-GC")
				assert(machine.configuration[1].id == "Great-GrandchildA")
				machine:Send("CB-CA")
				assert(machine.configuration[1].id == "GrandchildA")
				machine:Send("CA-GD")
				assert(machine.configuration[1].id == "Great-GrandchildD")
				machine:Send("CB-CA")
			end)
		end)

		it("should allow parallel states", function()
			expect(function()
				machine:Send("CA-CC")
				assert(machine.configuration[1].id == "GrandchildE" or machine.configuration[1].id == "GrandchildF")
				assert(machine.configuration[2].id == "GrandchildE" or machine.configuration[2].id == "GrandchildF")
			end).never.to.throw()
		end)

		it("should exit and destroy", function()
			expect(function()
				machine:Stop()
			end).never.to.throw()
			expect(function()
				error(machine._running)
			end).to.throw(false)
		end)
	end)
end
