# Brand and legal rules

Max Q works with SpaceXAI's and X's products without pretending to be one of them. These rules are load-bearing; changes to UI copy, icons, the website or store listings must keep to them.

## Names

- The product name never contains **Grok**, **xAI**, **SpaceX**, **SpaceXAI** (or SpaceXSI), or a standalone **X**. SpaceXAI's brand guidelines forbid using their marks in a third-party app's name or domain.
- SpaceX product names (Starlink, Starship, Falcon, Dragon, Raptor, Merlin, Starbase) are never used as names for anything in Max Q.
- Their products are named only to describe what Max Q works with ("works with Grok", "open Grokipedia"). That is nominative use.

## Logos and icons

- No SpaceXAI, X or Grok logos are bundled in this repository or used as Max Q's icon.
- Launchers and tabs show each site's own icon, loaded at runtime from the site, the way every browser shows favicons. Grok Bot's launcher shows the installed app's own icon from macOS.
- Max Q's mark (an ascent trajectory with one bright point) and its monochrome look are its own.

## Affiliation

- Every surface that names their products also says Max Q is independent: the home page footer, the welcome screen, Settings > About, the README and NOTICE.
- Grok-generated text is labeled **"Written with Grok"**, as SpaceXAI's guidelines ask.
- Before mentioning SpaceXAI in press material, contact legal@x.ai first (their guideline).

## Access to their services

Each service is used through the way it publishes for that use, with the user's own keys and accounts:

- **Grok:** the official API with the user's own key, or grok.com itself in a web view with the user's own account. Max Q never scripts or automates grok.com, and the agent doesn't work there.
- **Grokipedia:** its pages and its own search, loaded in WebKit the way a browser loads them, only when the user searches or opens an article, one page at a time, and shown in Max Q's reader with a link to the page. Never its API: `/api/` is the one path its robots.txt disallows.
- **X:** x.com itself, in a tab and in the Posts on X tab, shown as X serves it; X's share intent link; and the API's `x_search` tool with the user's key. No paid X API, nothing read out of x.com, Max Q never posts anything itself, and the agent doesn't work on X.
- **Brave Search API:** the user's own key, tried with one small search before it's saved. Results are shown, not kept (a saved result keeps its link and title), and never sent to Grok or used to train or improve AI, as Brave's terms ask.
- **DuckDuckGo:** the suggestion address its OpenSearch description publishes for browsers, and links to its own pages. The agent's search opens DuckDuckGo's page in the tab, like a person would.
- **YouTube:** questions about a video read only the transcript panel the user opened under it.
- **News:** the outlets' own RSS feeds.
- **Grok Bot:** opened as an app, given work through its own email inbox via the user's mail app. Its undocumented URL routes are not used.
- **The agent** stays off banking, payment and password sites, and off sites whose terms forbid automated use (X, grok.com, YouTube, Amazon, LinkedIn, Meta's, Reddit, TikTok, Google's results).

## If Max Q is ever released as an app

It's shared as source only. A signed release would also need:

- A trademark clearance search on "Max Q" (NVIDIA uses "Max-Q" for laptops; a medical-imaging company called MaxQ AI exists).
- A look at the Developer ID signature, which shows the developer's legal name while the Apple account is an individual one.

Not legal advice. When in doubt, ask a trademark attorney.
