# Security

## Reporting a vulnerability

Please report security issues privately through GitHub's **Report a vulnerability** button on this repository (Security tab), not in a public issue. Include steps to reproduce and the Max Q version (Settings, About).

## What Max Q protects

- **Your SpaceXAI API key** is stored only in the macOS Keychain and sent only to `api.x.ai`.
- **Page content** is sent to SpaceXAI only when you ask Grok about a page, a selection, or your tabs.
- **Model output is untrusted.** Answers are rendered as text; only `http` and `https` links are clickable; nothing a model returns is executed.
- **Pages are untrusted input to Grok.** Page text is sent with an explicit "untrusted content" marker and hidden-text tricks (invisible, off-screen, zero-size text) are stripped before sending.
- **The address bar refuses `javascript:`, `data:`, `vbscript:` and `blob:`** so pasted text can't run script.
- **Links to other apps** (anything that isn't a web link) ask before opening, except `mailto:`.
- **App Sandbox** with only network, user-selected files, Downloads, camera and microphone (each site asks first), and printing.
