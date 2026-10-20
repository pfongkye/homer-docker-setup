# Slack app

Each person uses their own Slack app: Slack sends commands to a single URL per app, which is your Homer tunnel.

## 1. Create the app

1. https://api.slack.com/apps → Create New App → From an app manifest → pick the workspace.
2. Paste Homer's [manifest.json](https://github.com/ManoManoTech/homer/blob/main/manifest.json). Leave `HOMER_BASE_URL` as is, `start-tunnels.sh` replaces it.
3. Create, then Install to Workspace.
4. Optional: add Homer's [custom emojis](https://github.com/ManoManoTech/homer/tree/main/emojis) to the workspace so messages render properly.

## 2. Tokens for `.env`

| `.env` key | Where |
|---|---|
| `SLACK_BOT_USER_O_AUTH_ACCESS_TOKEN` | OAuth & Permissions → Bot User OAuth Token (`xoxb-…`) |
| `SLACK_SIGNING_SECRET` | Basic Information → App Credentials → Signing Secret |
| `SLACK_APP_ID` | Basic Information → App ID |
| `SLACK_CONFIG_ACCESS_TOKEN`, `SLACK_CONFIG_REFRESH_TOKEN` | https://api.slack.com/apps → Your App Configuration Tokens → Generate Token, for your workspace |

The configuration access token expires after 12 hours. `start-tunnels.sh` rotates it with the refresh token and writes both new tokens back to `.env`. A refresh token works once: if a run is interrupted mid-rotation, generate a new pair.

Without `SLACK_APP_ID`, the script skips Slack and you update the slash command and interactivity URLs yourself in the app settings.

## 3. Channels

1. Create the channels used for releases and notifications, and invite the app (`/invite @Homer`).
2. Channel ID: open the channel → channel name → About, bottom of the panel (`C…`).
3. Use the IDs in `homer-config/projects.json` and for `SLACK_SUPPORT_CHANNEL_ID`.
4. Link a GitLab project to a channel with Homer's `/homer project add` command, see [Homer's usage guide](https://github.com/ManoManoTech/homer#usage).
