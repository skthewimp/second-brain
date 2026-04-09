I tried another round of therapy late last year, and one of the things my therapist told me was that I need to externalise my thinking. She's right. I think constantly - about career stuff, business ideas, patterns I notice in random conversations - but I lose track of all of it. The worst part isn't forgetting. The worst part is going in circles. I'll have the same career anxiety on a Tuesday walk that I had three Tuesdays ago, and it feels completely fresh each time because I've forgotten I already thought through it.

She didn't tell me how to build one, though.

A couple of weeks ago, Andrej Karpathy posted this gist about building a personal wiki maintained by an LLM. The idea is that instead of doing RAG every time you ask a question (search through a pile of documents, stuff relevant chunks into context), you have the LLM incrementally build a structured wiki. Each new piece of information gets woven into what's already there. The wiki compounds. I read it and immediately knew what I wanted to use it for.

My daughter suggested I call it "Pensieve" (yes, the Harry Potter thing where Dumbledore pulls silvery memories out of his head and drops them in a bowl to examine later). That's basically what this is.

So I built it over a weekend with Claude Code. On my phone, I just talk. Hit record, ramble for thirty seconds about whatever I'm thinking, hit stop. WhisperKit does the transcription on-device (runs on the iPhone's Neural Engine, no network needed), then the Claude API extracts themes, emotional tone, key quotes. The processed note gets saved as markdown into an Obsidian vault that syncs to my Mac via iCloud.

The Karpathy-inspired part is what happens on the Mac. A daily script runs Claude Code against the vault - it reads new raw notes, creates or updates theme pages, maintains a timeline, and tracks contradictions. That last bit is the whole point, really. When I say something that conflicts with what I said two weeks ago, it flags it. When I'm revisiting a topic for the fourth time without resolution, it notes that too. The wiki schema (which is itself a CLAUDE.md file that tells Claude Code how to maintain everything) has this rule: "Flag patterns, don't prescribe." It's not trying to tell me what to do. It's showing me where my thinking keeps circling back.

I did some reading on personal knowledge management systems and how they tend to fail. The consensus is interesting - the number one reason these systems die is that they become write-only. Notes go in, nothing useful comes out, you feel guilty about not doing your weekly review, you avoid the system, it dies. Zero-friction capture is necessary but not sufficient. You also need the system to push things back at you.

I haven't built that part yet. Deliberately. I've been using it for a few days and I want to see what my notes actually look like before I start engineering digest emails or push notifications. How many notes do I actually record in a week? What do the themes look like? Is the contradiction detection useful or noisy? Building retrieval features for a system I haven't really stress-tested yet feels like premature optimisation.

The whole thing is on GitHub at [github.com/skthewimp/pensieve](https://github.com/skthewimp/pensieve) if you want to poke at it. The `CLAUDE.md` wiki schema is probably the most reusable part - you could adapt it for any personal wiki even without the iOS app.

For now I'm just talking into my phone on walks and seeing what accumulates.
