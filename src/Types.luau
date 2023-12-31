--[=[
	@class Arch
	This is the Arch class
]=]
--[=[
@type Context { janitor: any, event: string, Send: (string, any) -> (), target: string?, any: any, }
@within Arch ]=]
--[=[
@type Options { id: string, context: { any }?, actions: { string: (Context, any) -> () }?, guards: { string: (Context, any) -> boolean }?, maxLogs: number?, logTime: boolean?, debugMode: boolean?, }
@within Arch ]=]
--[=[
@type Action (Context, any) -> ()
@within Arch ]=]
--[=[
@type Transition string | { target: string?, actions: { string | Action }?, guards: { string | Action }? } | { { target: string?, actions: { string | Action }?, guards: { string | Action }? } }
@within Arch ]=]
--[=[
@type AtomicState { id: string, OnEntry: ( string | Action )?, OnExit: ( string | Action )?, events: { string: Transition }? }
@within Arch ]=]
--[=[
@type CompoundState AtomicState & { initial: string, states: States }
@within Arch ]=]
--[=[
@type ParallelState AtomicState & { parallel: true, states: States }
@within Arch ]=]
--[=[
@type HistoryState CompoundState & { history: string }
@within Arch ]=]
--[=[
@type Definition {id: string, initial: string?, parallel: boolean?, states: { string: ( CompoundState | AtomicState | HistoryState | ParallelState ) } } | ModuleScript
@within Arch
]=]
type Action = (Context, any) -> ()
type Guard = (Context, any) -> boolean

export type Context = { janitor: any, event: string, Send: (string, any) -> (), target: string?, any: any }

export type Transition =
	string
	| { target: string?, actions: { string | Action }?, guards: { string | Action }? }
	| { { target: string?, actions: { string | Action }?, guards: { string | Action }? } }

type AtomicState = {
	id: string,

	OnInit: ((Context, any) -> ())?,
	OnEntry: ((Context, any) -> ())?,
	OnExit: ((Context, any) -> ())?,
	OnDestroy: ((Context, any) -> ())?,

	events: { string: Transition }?,
}
type CompoundState = {
	id: string,
	initial: string,

	OnInit: ((Context, any) -> ())?,
	OnEntry: ((Context, any) -> ())?,
	OnExit: ((Context, any) -> ())?,
	OnDestroy: ((Context, any) -> ())?,

	events: { string: Transition }?,
	states: States,
}
type HistoryState = {
	id: string,
	initial: string,
	history: string,

	OnInit: ((Context, any) -> ())?,
	OnEntry: ((Context, any) -> ())?,
	OnExit: ((Context, any) -> ())?,
	OnDestroy: ((Context, any) -> ())?,

	events: { string: Transition }?,
	states: States,
}
type ParallelState = {
	id: string,
	parallel: true,

	OnInit: ((Context, any) -> ())?,
	OnEntry: ((Context, any) -> ())?,
	OnExit: ((Context, any) -> ())?,
	OnDestroy: ((Context, any) -> ())?,

	events: { string: Transition }?,
	states: States,
}

type States = { string: CompoundState | AtomicState | HistoryState | ParallelState }

export type Definition = {
	id: string,
	initial: string?,
	parallel: boolean?,

	states: States,
}

export type Options = {
	id: string?,
	context: { any }?, -- sets the initial context of the machine passed to each state
	actions: { string: Action }?, -- dictionary of actions that can be referenced by state and transition callbacks by setting them equal to a key in this dictionary
	guards: { string: Guard }?, -- dictionary of guards that can be referenced by transitions by setting them equal to a key in this dictionary
	maxLogs: number?, -- the max logs allowed in the log history at a time before the oldest log gets deleted
	logTime: boolean?, -- determines whether or not to include a time property to each log
	debugMode: boolean?, -- prints steps taken throughout the lifecycle for easier bug diagnosis
}

return 0
