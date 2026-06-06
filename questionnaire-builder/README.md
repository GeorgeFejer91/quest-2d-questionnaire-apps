# Quest Questionnaire Builder

This folder is the static GitHub Pages version of the questionnaire builder.
It can edit configs and import trigger catalogs entirely in the browser.

Local build actions require the Windows companion running on the user's PC:

`powershell
Start-QuestionnaireBuilderOnlineConnector.cmd
`

That companion exposes a token-protected API at http://127.0.0.1:8765.
Enter the printed pairing token in the web UI before saving configs,
checking dependencies, validating configs, or generating APKs.

The hosted page is intentionally static. It does not install software or run
build tools directly; the local companion owns file system and build actions.
