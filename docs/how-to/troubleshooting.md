# Troubleshooting

## `docker compose up` or `down` hangs (Colima)

The docker daemon inside the VM is stuck, often at startup trying to clean up a container containerd still reports as running. `docker version` hangs too. Restart the VM:

```bash
colima stop && colima start
```

## Port already allocated

Another container already publishes 3000 or 5432 (`docker ps --format '{{.Names}} {{.Ports}}'`). Stop it, or change `HOMER_PORT` in `.env`. Keep `POSTGRES_PORT` at 5432: Homer also uses it as the port to connect to inside the compose network.

## CI job: `Failed to connect to localhost:8929`

The runner clones from GitLab's `external_url`. Register it with `--clone-url http://gitlab:8929`, or set `clone_url = "http://gitlab:8929"` under `[[runners]]` in `/etc/gitlab-runner/config.toml` of the runner container. See [gitlab-runner.md](gitlab-runner.md).

## Release messages do not progress

The project webhook lacks Deployment events. Enable them, see [gitlab-setup.md](gitlab-setup.md#4-the-webhook).

## Homer logs `Gitlab request received with wrong secret`

The webhook secret token differs from `GITLAB_SECRET`. Run `./start-tunnels.sh`, it sets it again.

## `start-tunnels.sh`: an ngrok agent is already running

The free ngrok plan allows one agent session. Stop the other `ngrok` process.

## `start-tunnels.sh`: `tooling.tokens.rotate failed`

The Slack refresh token was already used or revoked. Generate a new token pair (see [slack-app.md](slack-app.md#2-tokens-for-env)) and update `.env`.

## Homer fails to start after a fresh clone

`homer-config/projects.json` was missing when the container was created, so docker created a directory in its place. Remove it, copy `projects.example.json`, then `docker compose up -d homer`.

## Logs

```bash
docker compose logs -f homer
docker compose logs -f gitlab
```
