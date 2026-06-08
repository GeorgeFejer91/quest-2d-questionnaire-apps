# Quest Questionnaire Builder

This folder is the static GitHub Pages version of the questionnaire builder.
It can edit configs and import trigger catalogs entirely in the browser.

Local build actions require the Windows companion running on the user's PC:

`powershell
Start-QuestionnaireBuilderOnlineConnector.cmd
`

That companion opens a connected local builder page and exposes a token-protected
API at http://127.0.0.1:8776. Use the local page it opens when a browser blocks
hosted-to-loopback fetches.

The hosted page is intentionally static. It does not install software or run
build tools directly; the local companion owns file system and build actions.
