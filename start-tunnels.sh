#!/usr/bin/env bash
# Starts the stack, exposes homer and gitlab through ngrok, and points the
# GitLab project webhook at the new homer URL. Ctrl-C stops the tunnels.
# Prerequisites and required .env keys: see the "Prerequisites" and "Daily use" README sections.
set -euo pipefail

cd "$(dirname "$0")"

GITLAB_LOCAL_URL="http://localhost:8929"
NGROK_API="http://127.0.0.1:4040/api/tunnels"

fail() { echo "error: $*" >&2; exit 1; }

# An already exported variable wins over .env. Single keys are read rather than
# sourcing .env, because compose and bash parse that file differently.
env_value() {
  local value="${!1:-}"
  if [[ -z "$value" && -f .env ]]; then
    value=$(grep -E "^$1=" .env | tail -1 | cut -d= -f2- || true)
    value=${value%\"}; value=${value#\"}; value=${value%\'}; value=${value#\'}
  fi
  printf '%s' "${value:-${2:-}}"
}
require_env() {
  local value
  value=$(env_value "$1")
  [[ -n "$value" ]] || fail "$1 is not set (export it or add it to .env)"
  printf '%s' "$value"
}

# Writes through the existing file so .env keeps its permissions.
persist_env() {
  local tmp
  tmp=$(mktemp "${TMPDIR:-/tmp}/jug-homer-env.XXXXXX")
  KEY="$1" VALUE="$2" awk '
    BEGIN { k = ENVIRON["KEY"]; v = ENVIRON["VALUE"] }
    index($0, k "=") == 1 { print k "=" v; found = 1; next }
    { print }
    END { if (!found) print k "=" v }' .env > "$tmp"
  cat "$tmp" > .env
  rm -f "$tmp"
}

json_get() {
  python3 -c 'import json, sys; print(json.load(sys.stdin).get(sys.argv[1], ""))' "$1"
}
slack_error() {
  python3 -c 'import json, sys; r = json.load(sys.stdin); print("" if r.get("ok") else r.get("error", "unknown_error"))'
}

# Refresh tokens are single use, so the new pair is saved before anything else can fail.
rotate_slack_token() {
  local refresh response error token
  refresh=$(require_env SLACK_CONFIG_REFRESH_TOKEN)
  response=$(curl -fsS -X POST --data-urlencode "refresh_token=$refresh" https://slack.com/api/tooling.tokens.rotate)
  error=$(printf '%s' "$response" | slack_error)
  [[ -z "$error" ]] || fail "tooling.tokens.rotate failed: $error (generate new tokens at https://api.slack.com/apps)"
  token=$(printf '%s' "$response" | json_get token)
  persist_env SLACK_CONFIG_REFRESH_TOKEN "$(printf '%s' "$response" | json_get refresh_token)"
  persist_env SLACK_CONFIG_ACCESS_TOKEN "$token"
  echo "Rotated the Slack configuration tokens and saved them to .env" >&2
  printf '%s' "$token"
}

# Reads an apps.manifest.export response on stdin, prints the manifest pointed at
# $1, or nothing when it already is. Changed URLs are reported on stderr.
rewrite_manifest() {
  python3 -c '
import json, sys
base = sys.argv[1] + "/api/v1/homer"
manifest = json.load(sys.stdin)["manifest"]
changes = []
def point(obj, key, url, label):
    if obj.get(key) != url:
        changes.append("  %s: %s -> %s" % (label, obj.get(key), url))
        obj[key] = url
for command in manifest.get("features", {}).get("slash_commands", []):
    point(command, "url", base + "/command", "slash command " + command.get("command", "?"))
settings = manifest.get("settings", {})
if "interactivity" in settings:
    point(settings["interactivity"], "request_url", base + "/interactive", "interactivity")
if "event_subscriptions" in settings:
    point(settings["event_subscriptions"], "request_url", base + "/event", "event subscriptions")
if changes:
    print("\n".join(changes), file=sys.stderr)
    json.dump(manifest, sys.stdout)
' "$1"
}

update_slack_manifest() {
  local homer_url=$1 token response error manifest
  token=$(require_env SLACK_CONFIG_ACCESS_TOKEN)
  response=$(curl -fsS -X POST -H "Authorization: Bearer $token" \
    --data-urlencode "app_id=$SLACK_APP_ID" https://slack.com/api/apps.manifest.export)
  error=$(printf '%s' "$response" | slack_error)
  if [[ "$error" == token_expired || "$error" == invalid_auth ]]; then
    token=$(rotate_slack_token)
    response=$(curl -fsS -X POST -H "Authorization: Bearer $token" \
      --data-urlencode "app_id=$SLACK_APP_ID" https://slack.com/api/apps.manifest.export)
    error=$(printf '%s' "$response" | slack_error)
  fi
  [[ -z "$error" ]] || fail "apps.manifest.export failed: $error"

  echo "Slack app $SLACK_APP_ID manifest:"
  manifest=$(printf '%s' "$response" | rewrite_manifest "$homer_url")
  if [[ -z "$manifest" ]]; then
    echo "  already up to date"
    return
  fi
  if [[ "$DRY_RUN" == true ]]; then
    echo "  dry run, not updated"
    return
  fi
  response=$(curl -fsS -X POST -H "Authorization: Bearer $token" \
    --data-urlencode "app_id=$SLACK_APP_ID" --data-urlencode "manifest=$manifest" \
    https://slack.com/api/apps.manifest.update)
  [[ -z "$(printf '%s' "$response" | slack_error)" ]] || fail "apps.manifest.update failed: $response"
  echo "  updated"
}

check_prerequisites() {
  local cmd
  for cmd in docker ngrok curl python3 grep sed; do
    command -v "$cmd" >/dev/null || fail "'$cmd' is not installed or not on PATH"
  done
  [[ -f .env ]] || fail ".env is missing; copy .env.example to .env and fill it in"
  # Without the file, the bind mount would make docker create a directory in its place.
  [[ -f homer-config/projects.json ]] \
    || fail "homer-config/projects.json is missing; copy homer-config/projects.example.json and fill it in"
  docker info >/dev/null 2>&1 || fail "the docker daemon is not reachable"
  docker compose up --help 2>/dev/null | grep -q -- '--wait-timeout' \
    || fail "docker compose v2 with 'up --wait' is required"
  NGROK_CONFIG=$(ngrok config check 2>/dev/null | sed -n 's/^Valid configuration file at //p')
  [[ -n "$NGROK_CONFIG" ]] || fail "no valid ngrok config; run 'ngrok config add-authtoken <token>'"
  [[ -n "${NGROK_AUTHTOKEN:-}" ]] || grep -q authtoken "$NGROK_CONFIG" \
    || fail "no ngrok authtoken; run 'ngrok config add-authtoken <token>'"
  # The free ngrok plan allows a single agent session, so both endpoints share one agent.
  if pgrep -x ngrok >/dev/null; then
    fail "an ngrok agent is already running (pid $(pgrep -x ngrok | tr '\n' ' ')); stop it first"
  fi
}

DRY_RUN=false
case "${1:-}" in
  "") ;;
  --dry-run) DRY_RUN=true ;;
  *) fail "usage: $0 [--dry-run]" ;;
esac

check_prerequisites
SLACK_APP_ID=$(env_value SLACK_APP_ID)
GITLAB_TOKEN=$(require_env GITLAB_TOKEN)
GITLAB_SECRET=$(require_env GITLAB_SECRET)
GITLAB_NGROK_DOMAIN=$(env_value GITLAB_NGROK_DOMAIN)
GITLAB_WEBHOOK_PROJECT=$(require_env GITLAB_WEBHOOK_PROJECT)
GITLAB_WEBHOOK_ID=$(require_env GITLAB_WEBHOOK_ID)
HOMER_PORT=$(env_value HOMER_PORT 3000)
gitlab_url_line=""
[[ -n "$GITLAB_NGROK_DOMAIN" ]] && gitlab_url_line="url: https://${GITLAB_NGROK_DOMAIN#https://}"

echo "Starting docker compose and waiting for healthchecks (gitlab can take several minutes)..."
docker compose up -d --wait --wait-timeout 900

tunnels_config=$(mktemp "${TMPDIR:-/tmp}/ngrok-jug-homer.XXXXXX")
ngrok_log=$(mktemp "${TMPDIR:-/tmp}/ngrok-jug-homer-log.XXXXXX")
cat > "$tunnels_config" <<EOF
version: 3
endpoints:
  - name: homer
    upstream:
      url: $HOMER_PORT
  - name: gitlab
    $gitlab_url_line
    upstream:
      url: 8929
EOF

ngrok start --all --config "$NGROK_CONFIG" --config "$tunnels_config" --log "$ngrok_log" >/dev/null &
ngrok_pid=$!
trap 'kill "$ngrok_pid" 2>/dev/null; rm -f "$tunnels_config"' EXIT

tunnel_url() {
  local url="" response
  for _ in $(seq 1 30); do
    kill -0 "$ngrok_pid" 2>/dev/null || { echo "error: ngrok exited, log:" >&2; cat "$ngrok_log" >&2; exit 1; }
    # The agent API answers only once ngrok has started.
    response=$(curl -fsS "$NGROK_API" 2>/dev/null || true)
    if [[ -n "$response" ]]; then
      url=$(printf '%s' "$response" | python3 -c '
import json, sys
for t in json.load(sys.stdin)["tunnels"]:
    if t["name"] == sys.argv[1]:
        print(t["public_url"])' "$1")
    fi
    [[ -n "$url" ]] && break
    sleep 1
  done
  [[ -n "$url" ]] || fail "$1 tunnel did not come up in 30s, log: $ngrok_log"
  printf '%s' "$url"
}
homer_url=$(tunnel_url homer)
GITLAB_PUBLIC_URL=$(tunnel_url gitlab)

webhook_url="$homer_url/api/v1/homer/gitlab"
if [[ "$DRY_RUN" == true ]]; then
  echo "Dry run: would update webhook $GITLAB_WEBHOOK_ID of $GITLAB_WEBHOOK_PROJECT to $webhook_url"
else
  echo "Updating webhook $GITLAB_WEBHOOK_ID of $GITLAB_WEBHOOK_PROJECT to $webhook_url"
  # A PUT with only url and token keeps the hook's enabled events unchanged.
  curl -fsS -o /dev/null -X PUT \
    -H "PRIVATE-TOKEN: $GITLAB_TOKEN" \
    --data-urlencode "url=$webhook_url" \
    --data-urlencode "token=$GITLAB_SECRET" \
    "$GITLAB_LOCAL_URL/api/v4/projects/${GITLAB_WEBHOOK_PROJECT//\//%2F}/hooks/$GITLAB_WEBHOOK_ID"
fi

if [[ -n "$SLACK_APP_ID" ]]; then
  update_slack_manifest "$homer_url"
else
  echo "SLACK_APP_ID not set, skipping the Slack manifest"
fi

echo
echo "homer:   $homer_url"
echo "gitlab:  $GITLAB_PUBLIC_URL"
echo "webhook: $webhook_url"
echo "ngrok log: $ngrok_log — Ctrl-C to stop the tunnels"
wait "$ngrok_pid"
