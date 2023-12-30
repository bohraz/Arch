---
sidebar_position: 3
---
# Core Concepts

## Machines

### Defining Machines
As mentioned earlier, there are two ways to define a machine during creation: with a dictionary or with a file hierarchy.
#### Dictionary
```lua title="Dictionary.lua"
local myMachineDefinition = {
    id = "myMachine",
    initial = "StateA",

    states = {
        StateA = {
            initial = "ChildStateA",

            states = {
                ChildStateA = {}
            }
        }
    }
}

local myMachine = Arch.createMachine(myMachineDefinition)
```
#### File Hierarchy
Using a file hierarchy instead of a dictionary is useful for machines that have many layers of state nesting.  
To create a machine with a file hierarchy, you simply create a ModuleScript for the machine and each state and set the hierarchy accordingly. You can exclude the `states` property of each state because `createMachine` automatically builds it based on the file hierarchy. Finally, pass the machine ModuleScript Instance as the definition for `createMachine`. Here's an example:
```lua title="myMachine.lua"
local myMachine = {}

myMachine.id = "myMachine"
myMachine.initial = "StateA"

return myMachine
```
```lua title="StateA.lua"
--child of myMachine
local state = {}

state.id = "StateA"
state.initial = "ChildStateA"

return state
```
```lua title="ChildStateA.lua"
--child of StateA
local state = {}

state.id = "ChildStateA"

return state
```
```lua title="initializeMyMachine.lua"
local myMachineFile = path.to.myMachine -- do not require, you must pass the actual ModuleScript Instance

local myMachine = Arch.createMachine(myMachineFile)
```
### Options
The `options` dictionary, which is the optional second parameter of `createMachine`, consists of several properties that change the behavior of the state machine or act as references for it.  
```lua
local options = {
    context = {}, -- the initial context of the machine passed to each state
    actions = {}, -- dictionary of actions that can be referenced by state and transition callbacks
    guards = {}, -- dictionary of guards that can be referenced by transitions
    maxLogs = 30, -- max logs in the log history, when the max is reached it deletes the oldest log
    logTime = true, -- wip determines whether or not to include a time property to each log
    debugMode = true, -- when set to true, the machine will print basic changes in the machine such as entering and exiting of states
}

local myMachine = Arch.createMachine(myMachineFile, options)
```

## States
States are the building blocks of all state machines.
### Atomic States
An atomic state is a state without any child states.
### Compound States
One of the most powerful concepts in Arch is that states can have children states nested in them. These are called compound states, and their child states can have children states of their own proceeding to any depth. Ultimately we will reach a state that has no children, which is an atomic state. When a compound state is active, one and only one of its children is active. Every compound state must have an `initial` property which specifies the child state to be automatically entered after the compound state is entered.
```lua
local myMachineDefinition = {
    id = "myMachine",
    initial = "StateA",
    states = {
        StateA = {
            initial = "ChildStateA",

            states = { -- simply include a states table to make a compound state
                ChildStateA = {}
            }
        }
    }
}
```
### History States
History states are compound states that include the `history` property, which can be set to `shallow` or `deep`. Before the state machine exits a compound state, it records the state's active descendants. If the history type is `deep`, the state machine remembers all of the active descendants, down to the atomic descendant(s). If the history type is `shallow`, the state machine remembers only which immediate child was active. When a transition takes a history state as its target, it enters the remembered states instead of those designated by `initial` properties.
```lua
local myMachineDefinition = {
    id = "myMachine",
    initial = "myHistoryState",
    states = {
        myHistoryState = {
            initial = "ChildA", -- initial must still be included for the first time the history state is entered
            history = "shallow", -- or "deep"
            states = {
                ChildA = {},
                ChildB = {}
            }
        }
    }
}
```
### Parallel States
A parallel state, denoted by setting the `parallel` property of a compound state to true, is a state whose children are active at the same time. Whereas when a state machine enters a compound state it enters only one of its children, when a state machine enters a parallel state it enters *all* of its children. Transitions within the individual child elements operate normally. However whenever a transition is taken with a target outside the parallel state, the parallel state and all of its child states are exited and the corresponding OnExit handlers are executed.  
```lua
local myMachineDefinition = {
    id = "myMachine",
    parallel = true, -- the initial property should be excluded if parallel is true
    states = {
        StateA = {}, -- both StateA and StateB will be active at the same time
        StateB = {},
    }
}
```
Note that the semantics of the parallel state does not call for multiple threads or truly concurrent processing. The children of parallel states execute in parallel in the sense that they are all simultaneously active and each one independently selects transitions for any event that is received. However, the parallel children process the event in a defined, serial order, so no conflicts or race conditions can occur.

## Transitions
A transition is a change from one state to another, triggered by an event. It is important to consider that the existence of compound states implies that a transition may not just change from one state to another, but from one hierarchy of states to another.  
Transitions are "deterministic", meaning each combination of state and event always points to the same next state. When a state machine receives an event, only the active states are checked to see if any of them have a transition for the event. The state that is being transitioned from is called the source, and the state that is being transitioned to is called the target.

### Creating transitions
Transitions are created by adding an events property to a state. The following examples, which have the same effect, show the three unique ways to create a transition.
```lua
local state = {}

state.id = "StateA"
state.events = {
    Event1 = "StateB", -- shorthand 
    Event2 = { target = "StateB" }, -- allows for greater customizability of the transition
    Event3 = { { target = "StateB" } }, -- allows for multiple transitions in a single event, we will cover this next
}

return state
```

### Guards & Actions
Transitions can include a list of guards, which are functions that must return true in order to accept a transition. If an event has multiple transitions, the state machine checks each transition in order until all of a transition's guards return true, that becomes the selected transition. Guards can be literal functions or string references to the guards property of `options`. In the following example of an Idle state for a combat system, if the player activates their tool the state machine will check first if the player isJumping, a reference to the guards in `options`. If so, then a jump attack will play. If not, the state machine will check if the player isCrouching and if so perform a trip attack.
```lua
state.id = "Idle"
state.events = {
    ToolActivated = {
        { target = "Jump Attack", guards = {"isJumping"} },
        { target = "Trip Attack", guards = {"isCrouching"} }
    }
}
```
Transitions can also include a list of actions, which are functions that are to be called between exiting the source states and entering the target states. These actions can be literal functions or string references to the functions in the actions property of `options`. The actions specified in the actions table of a transition are executed in order. In the following example, guards and actions are used for a directional walking system.
```lua
state.events = {
    updateWalkDirection = { guards = { "isDifferentDirection" }, actions = { "exitAnimation", "enterWalking" } }
}
```
### Delayed (after) transitions
Delayed transitions are transitions that happen automatically after a specific interval of time. They are denoted in the "after" property of the events table like so:
```lua
state.events = {
    after = { target = "StateB", delay = 3 } -- automatically transitions to StateB after 3 seconds if no other transitions are called
}
```