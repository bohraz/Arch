---
sidebar_position: 2
---
# Getting Started

To get started with Arch, follow these steps:

## Installation:
Include the Arch library in your Roblox project by installing it with wally or the [Roblox Model](https://create.roblox.com/marketplace/asset/15814653597) and requiring it from the appropriate directory.

```toml title="wally.toml"
[dependencies]
Arch = "bohraz/arch@0.2.1"
```
```lua
local Arch = require(path.to.Arch)
```

## Define States and Transitions:  
Model your game's behavior by defining states and transitions within the Arch framework. Utilize the hierarchical structure to organize states efficiently.

```lua
local myStateMachine = Arch.createMachine({
    id = "myStateMachine",
    initial = "idle",
    states = {
        idle = {
            OnEntry = function() print("Entering idle state") end,
            OnExit = function() print("Exiting idle state") end,
            events = {
                startRunning = "running"
            }
        },
        running = {
            initial = "regularRunning"
            OnEntry = function() print("Entering running state") end,
            OnExit = function() print("Exiting running state") end,
            events = {
                stopRunning = "idle"
            },
            states = {
                regularRunning = {
                    events = {
                        jump = "runningAndJumping"
                    }
                },
                runningAndJumping = {
                    OnEntry = function() print("Entering running and jumping state") end,
                }
            }
        },
    },
})
```

##  Start the State Machine and Send Events:  
Initiate and start the state machine to begin managing states and handling transitions.

```lua
myStateMachine:Start()
```

Use the `Send` method to trigger events and facilitate transitions between states.

```lua
myStateMachine:Send("startRunning")
```