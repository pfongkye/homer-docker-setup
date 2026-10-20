# AI Agent Instructions for homer-docker-setup

CRITICAL: When you encounter a file reference (e.g., @rules/general.md), use
your Read tool to load it on a need-to-know basis. They're relevant to the
SPECIFIC task at hand.

## Project Overview

A local environment to run [Homer](https://github.com/ManoManoTech/homer), the
Slack bot that shares GitLab merge requests and drives releases, against a
local GitLab CE, its CI runner and a personal Slack app. There is no
application code here: only docker compose, configuration, a Homer release
plugin and the `start-tunnels.sh` script.

Exposure: everything runs locally, but `start-tunnels.sh` publishes Homer and
GitLab on public ngrok URLs while it runs. Homer's endpoints authenticate
callers (Slack signing secret for `/command` and `/interactive`, the
`X-Gitlab-Token` header equal to `GITLAB_SECRET` for `/gitlab`); there is no
JWT. The GitLab tunnel exposes the GitLab login page, so `GITLAB_ROOT_PASSWORD`
must be strong.

## Technology Stack

* Docker Compose v2 (`docker compose up --wait` is required)
* Homer `ghcr.io/manomanotech/homer:v2.3.0` (Node.js, Express)
* Postgres 16 (`postgres:16-alpine`)
* GitLab CE and GitLab Runner, `latest` images, docker executor
* ngrok agent v3, one agent session serving both endpoints
* Bash 3.2 compatible scripting (macOS default), `curl`, `python3` for JSON

See `docker-compose.yml` for images and ports, `.env.example` for every
setting.

## Resources

* `README.md` – what runs, prerequisites, first setup, daily use
* `docs/how-to/README.md` – index of the setup guides:
  * `docs/how-to/gitlab-setup.md` – root login, Homer's user and token,
    project, webhook, `projects.json`
  * `docs/how-to/gitlab-runner.md` – registering the runner, why each flag
  * `docs/how-to/slack-app.md` – Slack app, tokens, channel IDs
  * `docs/how-to/troubleshooting.md` – known failures and fixes
* `start-tunnels.sh` – starts the stack, the ngrok tunnels, updates the
  GitLab webhook and the Slack app manifest
* `homer-plugins/release/simpleReleaseManager.js` – release manager plugin
  mounted into Homer; waits for a `build_image` job
* `homer-config/projects.example.json` – template of the projects Homer
  manages releases for; the real `projects.json` is gitignored
* `examples/sample-project/.gitlab-ci.yml` – pipeline exercising the release
  flow

## Rules

No mm-agents language rules apply: this repository has no application code.
For commits follow the user's git conventions; never stage `.env`,
`homer-config/projects.json` or `config.toml`.

## Behaviour

* Secrets live in `.env`. Never print, log, commit or paste their values. To
  call the GitLab API with Homer's token, run the call inside the container so
  the token stays there, e.g.
  `docker exec homer node -e 'fetch(process.env.GITLAB_URL + "/api/v4/...", { headers: { "PRIVATE-TOKEN": process.env.GITLAB_TOKEN } }).then(r => r.json()).then(console.log)'`
* Inside the compose network GitLab is `http://gitlab:8929`; from the host it
  is `http://localhost:8929`. Most runner and webhook issues come from mixing
  the two.
* Runner setup: follow `docs/how-to/gitlab-runner.md`; registration needs a
  `glrt-` token the user creates in the GitLab UI, ask for it rather than
  inventing one. Always register with `--clone-url http://gitlab:8929` and
  `--docker-network-mode homer-network`.
* GitLab takes minutes to become healthy. Wait with
  `docker compose up -d --wait`, never with fixed sleeps.
* If a docker command hangs, check the daemon (`docker version`) before
  retrying; see `docs/how-to/troubleshooting.md`.
* Ask before destructive actions: `docker compose down -v` deletes GitLab and
  Postgres data, `colima stop` stops every container on the machine.
* Changing `.env` or `projects.json` requires `docker compose up -d homer`.
* `start-tunnels.sh` must stay bash 3.2 compatible and portable between macOS
  and Linux (no GNU-only or BSD-only flags). Run `bash -n start-tunnels.sh`
  after editing, and `./start-tunnels.sh --dry-run` to check the planned
  changes without writing them.
* Keep `README.md`, `.env.example` and `docs/how-to/` in sync when adding a
  setting or a step.

## Utils

No MCP server is needed: use `docker`, `docker compose`, `curl` against the
GitLab API and the ngrok agent API (`http://127.0.0.1:4040/api/tunnels`).
