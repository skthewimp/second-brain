A couple of weeks ago I caught myself about to have the same career-anxiety monologue I'd had on a walk three Tuesdays earlier. Same priors, same conclusions, same "and so what now?" - feeling completely fresh, because I'd thoroughly forgotten I'd already thought through it. The worst part of constant thinking isn't forgetting. It's looping.

Around the same time, Andrej Karpathy posted a gist about building a personal wiki maintained by an LLM. The basic funda: instead of doing RAG every time you ask a question (search through documents, stuff chunks into context), you have an LLM incrementally weave new information into a structured wiki. The wiki *compounds*. I read it and immediately knew what I wanted to use it for.

So over a weekend with Claude Code, I built Pensieve. (My daughter named it. Yes, the Harry Potter thing where Dumbledore extracts memories into a bowl. That's basically the design spec.)

## How it works

On my phone: I hit record, ramble for thirty seconds about whatever, hit stop. WhisperKit does the transcription on-device - runs on the iPhone's Neural Engine, no network needed, the audio never leaves the device. Then the Claude API extracts a title, themes, emotional tone, key quotes, and tentative connections to other topics. The processed note saves as markdown into an Obsidian vault that syncs to my Mac via iCloud.

That covers capture. The interesting part is what happens on the Mac.

Originally I had Claude Code running against the vault every day to ingest the new notes - it would update theme pages, append to a timeline, and (most importantly) flag contradictions where my thinking had shifted. This worked, but it was expensive. Roughly $0.36 per note over a 10-note batch, mostly because Claude Code was doing a lot of agentic file-reading just to figure out the wiki state. So I rewrote the ingest as a small Swift binary called `pensieve-ingest` that makes a single direct Anthropic API call - the wiki state and the new notes go in, a JSON patch comes out, my Swift code applies it. Same outputs, ~33x cheaper. About a cent a note.

Two launchd jobs run on the Mac. One fires daily at 10:17am - if there are new notes, it ingests them and refreshes the mindmap. Quiet days cost nothing. The other fires Sunday at 23:00 and does a forced mindmap rebuild, useful when I've been iterating on the prompt and want the tree regenerated from scratch. The mindmap itself is a D3 radial tree rendered as a self-contained HTML file. I wanted something I could open in a browser and just *see* the shape of my own thinking, instead of yet another tool I had to learn.

## The contradictions page

This is the part I care about most. Every time the ingest runs, Claude looks for places where the new notes contradict positions in older notes, and writes them to `wiki/tensions/contradictions.md`. (The page is called "Contradictions and Shifts" because I want lower-stakes "I changed my mind" entries captured too, not only outright contradictions.)

The risk with this kind of thing is that a hallucinated contradiction is far worse than a missed one. A model that confidently tells me I'm contradicting myself when I'm not erodes trust in the whole wiki. So each contradiction is now tagged - `extracted` (verbatim quotes from two notes that literally clash, both sourced to specific note IDs), `inferred` (Claude's reading that two positions are in tension, even if I never said them as direct opposites), or `ambiguous` (might be a contradiction, depends on interpretation). I stole this from [safishamsi/graphify](https://github.com/safishamsi/graphify). The verbatim ones I trust. The inferred ones I read as "look at this". The ambiguous ones I read as "is this anything?"

## Text and URLs

Voice was the only input for the first couple of weeks. Then I noticed two gaps. I'd often be in environments where I couldn't talk out loud - offices, cafes, the bus. And I'd often be reacting to something I'd just read on the web. So I added a text box on the main screen, replacing the old-notes list which wasn't doing anything useful at capture time anyway.

The text box accepts free-form text. If there's a URL in it, the iOS app passes the URL to Claude along with my text, using the new server-side `web_fetch` tool. Claude fetches the article, treats it as the thing I'm reacting to, and treats my text as my take on it. The themes that come out reflect the take, not just the article summary. Paywalled articles fail gracefully - the note still saves with my text, just without the article context, and the frontmatter records `article_fetched: false` so I know which is which.

## One-tap capture

The other thing I added recently was a Lock Screen shortcut. I'd noticed that even with the app on my home screen, there was a noticeable gap between "I want to record this thought" and "I am recording" - unlock, find app, tap, tap Start. Four steps. Doesn't sound like much. It is.

A Reddit post made the point sharper than I'd been making it to myself: capture and organisation are different jobs, and a five-second extra step is the difference between a habit that lasts ten years and one that dies on day three. So I added a `pensieve://record` URL scheme. The iOS Shortcut just opens that URL. The app catches it, starts recording immediately. Tap the same shortcut again - it stops, and the pipeline runs as usual. One tap to start, one to stop, no UI in between.

I have it on Back Tap (double-tap the back of the phone). From locked screen to recording in about a second.

## Where this goes

I've been deliberately not building retrieval features. The number one failure mode of personal-knowledge systems, from everything I've read, is that they become write-only - notes go in, nothing useful comes out, the user feels guilty about the unread pile, the system dies. Zero-friction capture is necessary but not sufficient. You also need the system to push things back at you - daily digests, "you're going in circles" alerts, related past notes surfaced when you start a new capture. All of that is on the list.

But before building any of it, I want to look at a few weeks of actual usage. How many notes do I actually record in a week? What do the themes look like? Is the contradiction detection useful or noisy? Engineering retrieval features for a system I haven't really stress-tested yet feels like premature optimisation.

The whole thing is on GitHub at [github.com/skthewimp/pensieve](https://github.com/skthewimp/pensieve) if you want to poke at it. The wiki schema (in the project's `CLAUDE.md`) is probably the most reusable bit - you could adapt it for any personal wiki even without the iOS app.

For now I'm just talking and typing into my phone and seeing what accumulates.
