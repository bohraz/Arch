---
sidebar_position: 2
---

# Getting Started
## Installation
### With Wally
Simply drop this snippet into wally, except replace `latest` with the latest Arch version.
```toml title="wally.toml"
[dependencies]
Arch = "bohraz/arch@latest"
```
## Quick Start
The quick start guide will help you get started with Arch. You will learn how to create a single-layer state machine and send events to it.
### Creating a machine
The simplest way to create a state machine is by passing a table into `Arch.createMachine`. The alternative is to pass a file hierarchy, which is described in later sections.

In the following code we create a machine named `toggleMachine` with `Active` and `Inactive` states and a `toggle` event that transitions between them.
```lua
local Arch = require(path.to.Arch)

local toggleMachine = Arch.createMachine({
    id = "toggleMachine",
    initial = "Inactive",

    states = {
        Active = {
            OnEntry = function(context, param1, param2)
                print("Toggle on!", param1, param2)
            end,
            OnExit = function(context)
                print("Toggle off!")
            end,

            events = {
                toggle = "Inactive"
            }
        },

        Inactive = {
            OnInit = function(context)
                print("Initializing inactive state!")
            end,

            events = {
                toggle = "Active"
            }
        }
    }
})
```
### Starting the machine and sending events
Now, all we have to do is start the machine and send events.
```lua
toggleMachine:Start() --> Initializing inactive state!
toggleMachine:Send("toggle", 1, 2) --> Toggle on! 1 2
```