# Roadmap

Max Q is a research project shared as source code. There are no releases planned: this is what's built, and what might be explored next.

## Built (v0.1)

- [x] Native WebKit browser: vertical tabs, groups, Spaces, split view, Reader, link previews, private windows, tracker blocking, session restore
- [x] Setup: name, Grok (grok.com or the user's own API key), how you search, the user's Brave Search API key
- [x] One results page: Grok's answer with named sources and follow-ups, web results, the Grokipedia article, Posts on X (x.com itself), Images, News and Videos
- [x] Grokipedia in a reader: contents, sources, links between articles, Listen, questions about the article
- [x] Grok side panel: chat with the user's key (streaming, sources, cost), grok.com with the user's account, what X is saying about a page
- [x] Agent mode: does a task in a tab, asks before anything that can't be taken back, stays off sensitive sites and sites that forbid automation
- [x] Check a claim, research within a budget, questions about articles and videos, Collections and briefs, Grok Imagine
- [x] News on the new-tab page from the outlets' feeds, followed searches, ⌘K, the Max Q bar, Shortcuts
- [x] Apple's on-device model for free jobs; French
- [x] Unit tests for parsing, URL handling, request building, the agent's rules

## Ideas

- Voice mode (SpaceXAI's realtime voice API, with the user's key)
- iCloud sync end to end (the code is there, off until an iCloud container is set up)
- More languages

## Not planned

- Releases, accounts or a Max Q server
- Paid X API features (a native timeline, posting): the X API bills the app's developer, which conflicts with a free app and users' own keys
- Reading posts out of X, using Grokipedia's API, or automating grok.com
