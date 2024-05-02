# Ramblings

## 2024-04-29

OK so this project is at a stage where I think it'd be nice just to do some freeform writing. I don't really know what to write but I feel an urge to sort of iron out the project now, because it doesn't feel well designed, more like a bunch of features got crammed together.

I thought I had it all figured out in my head, but maybe it wasn't so.

The game must be networked and for that to work there's sort of this logical event line where events come in from all players and we wait for all player input before rendering the frame. That's one way of doing it. Another is like they did with timelines in I don't remember the title but whatever, where you store A and B and just have dumb clients that lerp between keyframes. I feel like I don't truly like that model because I feel like you want to give all players an equal chance of giving input in time. I'd much rather slow the simulation down than have one player who feels everything is laggy be able to play but losing because of the poor performance. You could argue both ways here, but that's where I'm leaning. Another thing is the amount of data. I really don't want to be bottlenecked on network; I want to allow for truly epic scale - if we want that is to be defined, but let's not lock us in. So:

> Let's use deterministic lock step with action deltas.

I feel like we should also just stake out the design goals of the game. Some random thoughts are that we should stay close to the metal and do what inspires us. Maybe it's not super important to end up with astonishing results, or maybe it is. I feel like if we play it smart designing the core, we'll open up a playful joyful game building experience, and that's what will make or break the game in the end. So we should really focus and invest heavily in the tech. Right now, we're so far from building a game that we only have ourselves to serve. I say us but it's really only me so far. I guess me and myself in the past and myself in the future. Anybody's welcome to join, but to be fair, it's perhaps best considering how little time I have to sync my thoughts with others that it remains just me for the time being.

So, design goals, huh...

> Make a rock solid technical foundation which is fun to work on top of.

That'd be the main one at this point in time, but it serves no higher purpose. I mean you could argue that you don't need more than that, but we're not building an engine here as the main goal, we actually have a vision about an actual game. Let's just write down what we know and see what goals we can take out of that.

It's a game (yay) about dwarves (yay) fighting for glory (yay). The most prestigious dwarven house wins. I think it'd be fun to be able to achieve this through economy as well as warfare. It's a multiplayer RTS with three dimensional voxel terrain maps, where dwarves run around mining resources and producing goods. A blend between Dwarf Fortress, Gnomoria, Age of Empires, Minecraft, and The Settlers, ish. I want the maps to be finite in size, game sessions to take around an hour or two to finish, and for there to be elements of magic. The graphics should play in calm dreamy colorful tones, and ideally use PBR, and the sounds should play in 3D spatial. Ideally as much as possible is procedurally generated, including maps, textures, units, sounds, etc, because it plays to the indie vibe, but if we manage to find a way to create a good amount of content, we may tip parts on its head.

Two features that are sort of optional but that I really want to support is procedurally generated music, imagined and performed by dwarves in-game; you'd need to craft instruments, and they'd use them in their leisure time, boosting culture and prowess, which is a main objective anyway. I'd be sort of cool to have musicians in armies playing marches on the field, but we're unlikely to build that. To be able to build such features, we'll really need for the underlying systems to be flexible and easy to compose. I hope the ECS that I wrote up this past weekend will suffice, but my gut feeling is that the page storage may be too limiting. It won't perform well if we mostly have few entities per component type, but many component types, but I don't think that will be the case. I also think we can limit the amount of wasted up front allocation by individually limiting the max entity count per archetype rather than across.

We should have caves and mining and tree cutting, ore smelting, sawmills, planks, etc, and I wonder how to generate art for all these things. It's possible we just create some ugly 3D models ourselves to get us started and we simply take another pass over the game later, focusing on mechanics for now.

Other technical avenues I'd really want to investigate are path traced graphics and how to build cameras for easily browsing the "interiors" of spaces (what does that even mean? I'm thinking of a house, a cavern, a church, a great hall, but where does one space start and the other end? It seems really complicated to build some sort of automatic system to determine boundaries, I can think of way too many pathological cases...). Probably the easiest thing is to just do what many games have already done and slice through the Y layers with an XZ plane of your choice, browsing only the lower levels. Maybe it's possible to mostly do that but also show walls that reach upward behing the center of the screen or something, or toggle, etc, but it's important that the controls are manageable by players as well.

So what technical components do we require for this design, which are optional, and which are most important?

We definitely require the following:

- network
- graphics
- sound
- input

These lie at the most fundamental level, close to the OS. We already have all but network coupled up and working here on Linux, which is our main platform of choice for the foreseeable future, simply because we lack the time and interest to do better up front. Will this bite us later? Yes and no. Depending on how smart we're about the interfaces we build on top, we can allow this to work very well or very poorly for porting to other platforms. I think the critical insight is that we must not couple platform specific details into the interfaces of these systems. Arguably, we will need to perform some abstractions on top of them, like e.g. Vulkan graphics requires a window handle, which it gets from the windowing system, and which is used will depend on the platform. Maybe we should just consider this whole blob of systems to just be platform systems and then allow them to couple freely, but then build higher layers on top. That is what we'll do for now.

That also brings up the question of how we're going to interact with those systems. Let's take Vulkan, which has a very verbose API and a ton of footguns. Do we design our own wrapper around Vulkan? We will miss out on feature completeness, but there's a clear advantage of not spreading Vulkan code across the codebase. I think this is important. Arguably, the ideal model is as follows: the user inits the graphics system, telling it what memory to allocate, and we hardcode the major code paths we expect to take inside the graphics system; as need arises, we expose more functionality, and keep the interface simple; we don't skimp on performance, but e.g. write directly to graphics memory from the outside rather than use intermediate serialization structures. We'll see how feasible this gets, but I think it makes sense. The layers we build on top will still be fairly low level, and we'll likely require a bunch of layers before we arrive at something high level that's easy to play with like clay.

Right now I think we're mainly lacking answers for the following:

How will the technical outline of the game look?

We're currently lacking hot reloading, network, proper replays, a state machine, text drawing, tests, and a mod system (ecs systems?) which allow us to break game logic into completely separate pieces so we don't pollute main like we do now.
Let's address what impacts what.
Network impacts replays, so network must go first.
Hot reloading impacts mod system.
State machine impacts network.
So we should start with the state machine I guess.

After state machine, we tackle hot reloading, and then network, replays and ecs systems. Let's list that.

1. State machine
2. Hot reloading
3. Network
4. Replays
5. Mods

On top of this, we have an ugly bug with input: the way we batch input over frames doesn't work. Instead of batching up input and then reading the end state per input frame into actions, we must parse into actions continuously. The reason for this is that we want to lower the update frequency, and we ALREADY have a bug on some keyboards, where some keyboards may immediately send keydown and keyup events for the same key directly after each other, depending on its configuration. If these events arrive between update frames, we never process the keydown at all as it stands today. I'm not sure how to handle this nicely. On one hand I don't want to enqueue every message, e.g. intermediate mouse moves are irrelevant, it's the end position that really matters, unless we're performing gestures, which I don't think we will, and even then, we probably still only want to send the gesture action rather than every intermediate mouse cursor position. So, what we will have to do is still batch up; just not inputs, but actions. I don't like the idea of a variable size memory region for handling this, but I think it will be possible for fast players to perform more than one action per frame, especially if we lower the update frequency to e.g. 10hz. We need the queue. Something we could do is have an arena of actions, filled, compacted, used, and cleared per frame. I think this is the golden design.

Another interesting aspect of the input system is that if we only process the actions at update frames, which occur much more rarely than input, network and graphics frames, how do we represent something like "enter build mode" -> "enter build wall mode"? Should enter build wall mode be available before enter build mode? Maybe the answer is just yes here, but what about something where the former holds a context? E.g. "select unit" -> "command selected"? I think the interface must simply be like this: 1. we poll raw per-platform input, transform and push it to a platform-agnostic input queue, and fan out to allow multiple consumers to take turns to capture and swallow these events, possibly turning them into actions. It's important that we make this flexible and joyful to work with, and I think the nicest design is actually just to poll. We'd effectively have a multi consumer queue. It'd still be per-frame so we can arena it and allow them to have their own read cursors, per frame. The ugly part with this is that we allow use of raw input rather than using actions. It's important that we strictly only use actions rather than allowing raw input, or it's going to get messy enforcing the boundaries and make it hard to rebind keys. This means that we require the transformation of input into actions to be opaquely handled. I think the only way to make this happen is coupling the input event action system with a state machine which may transition with the actions.

Let's imagine designing input then as an FSM of states and events with a transition table in between. States and events are global and sparsity is handled by the transition table. How do we then attach information like mouse position? Perhaps we don't need to, as we will consider it to stay the same during the processing of our update frame. We could simply store it and look it up when required. Controller input, if relevant, could work the same. The problem, again, comes down to abstraction. If we want to use a gamepad instead of a mouse for whatever reason, e.g. to allow all your kids to play on the same computer, we'd better not hardcode to check for a mouse position. This could of course be separately handled. We can of course bend and resort to enum unions or variable size action payloads, at the cost of higher complexity, but let's avoid that until we realize we were dumb avoiding things, because I can't come up with a reason, despite having considered controller input and multiscreen support. There seem to me to be other better ways around this problem.