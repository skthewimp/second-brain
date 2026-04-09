My therapist told me I need a "second brain." She didn't tell me how to build one.

I have ADHD. I think constantly - about career moves, business ideas, patterns I notice in conversations, things I want to change about how I work. The problem isn't generating thoughts. The problem is that I lose them. Worse, I go in circles without realising it. I'll have the same career anxiety three weeks in a row, each time feeling like a fresh crisis, because I've forgotten I already worked through it last Tuesday on a walk.

The therapist's prescription was some kind of externalised thinking system. A place to dump thoughts with zero friction, and then actually look at them later to spot patterns. Most ADHD advice stops at "write things down in a journal." That's not a system. That's a graveyard with a nice cover.

A couple of weeks ago, Andrej Karpathy posted a gist about building a personal wiki maintained by an LLM. The idea is simple - instead of RAG (search a pile of documents every time you ask a question), you have the LLM incrementally build and maintain a structured wiki. The wiki compounds over time. Each new piece of information gets woven into what's already there.

I read it and immediately knew what I wanted to use it for.

The system I built has three parts. First, an iOS app where I just talk into my phone. That's it - that's the entire input mechanism. I hit record, ramble for thirty seconds about whatever's on my mind, and hit stop. WhisperKit transcribes it on-device (no network needed), then the Claude API extracts themes, emotional tone, key quotes, and connections to other topics. The processed note gets saved as markdown into an Obsidian vault.

Second, the Obsidian vault itself, which syncs via iCloud between my phone and Mac. I can browse my thoughts as a wiki with backlinks and a graph view.

Third - and this is the Karpathy-inspired bit - a daily ingestion script that runs Claude Code on my Mac. It reads any new raw notes, creates or updates theme pages, maintains a timeline, and most importantly, tracks contradictions. When I say something that conflicts with what I said two weeks ago, it flags it. When I'm revisiting a topic for the fourth time without resolution, it notes that too.

The contradictions page is the most valuable page in the whole system. The wiki schema has an explicit rule: "Flag patterns, don't prescribe." It's not trying to tell me what to do. It's showing me what I keep thinking about, and where my thinking has shifted or gone circular.

Building the thing took two days with Claude Code. The interesting bugs were all SwiftUI-related - there's this pattern where nested `ObservableObject`s don't propagate state changes to the UI, and I hit it three separate times before the lesson really sank in. The Obsidian vault linking was particularly entertaining - the app would claim the vault wasn't connected even after the user picked a folder, because the state change was invisible to SwiftUI.

I've deliberately held off on adding features. The ADHD second brain research I did suggests that the main failure mode isn't missing features - it's building a write-only system that you never look at again. So I'm collecting data for a week first. Using it, seeing what my notes actually look like, and then deciding whether I need things like daily digest emails or "you're going in circles" push notifications.

The whole thing is open source at [github.com/skthewimp/second-brain](https://github.com/skthewimp/second-brain). The wiki schema in `CLAUDE.md` is probably the most transferable part if you want to adapt it for your own use.

For now, I'm just talking into my phone on walks and seeing what accumulates. The system's job is to remember what I forget.
