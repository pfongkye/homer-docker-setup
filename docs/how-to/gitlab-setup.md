# GitLab setup

GitLab runs at http://localhost:8929. Inside the compose network Homer and CI jobs reach it as `http://gitlab:8929`.

## 1. Log in

User `root`, password `GITLAB_ROOT_PASSWORD` from `.env`. The password is only applied on the very first boot; changing it later in `.env` has no effect.

## 2. A user for Homer

Homer calls the GitLab API with `GITLAB_TOKEN`.

1. Admin area → Users → New user, e.g. `homer-service` (or a [service account](https://docs.gitlab.com/user/profile/service_accounts/) if your GitLab edition offers it).
2. As that user (or via Admin area → Users → Impersonate): Preferences → Access tokens → add a token with the `api` scope.
3. Put it in `.env` as `GITLAB_TOKEN`.

## 3. A project

Create a project, or push an existing repository:

```bash
git remote add local http://localhost:8929/<namespace>/<project>.git
git push local main
```

To try the release flow, commit [examples/sample-project/.gitlab-ci.yml](../../examples/sample-project/.gitlab-ci.yml): the release manager waits for a job named `build_image` to succeed on the default branch, and deployment events come from jobs with an `environment`.

Then Project → Manage → Members → invite `homer-service` as **Maintainer**. Without it, Homer cannot create tags and releases and webhook updates fail.

## 4. The webhook

Project → Settings → Webhooks → Add new webhook:

- URL: any `https://` placeholder, `start-tunnels.sh` replaces it with `<homer-url>/api/v1/homer/gitlab`
- Secret token: `GITLAB_SECRET` from `.env`
- Triggers: Push, Comments, Merge request, Job, Pipeline, Deployment events

Deployment events are required for release messages to progress. After saving, the edit URL ends in `/-/hooks/<id>/edit`: put `<id>` in `GITLAB_WEBHOOK_ID` and `<namespace>/<project>` in `GITLAB_WEBHOOK_PROJECT`.

The script updates a single webhook. For more projects, add a webhook to each with the same URL and secret, or use a group webhook.

## 5. `homer-config/projects.json`

One entry per project Homer manages releases for:

- `projectId`: Project → Settings → General, "Project ID"
- `releaseChannelId`, `notificationChannelIds`: Slack channel IDs, see [slack-app.md](slack-app.md)
- `releaseManager`: `simpleReleaseManager`, the plugin in `homer-plugins/release/`

Apply changes with `docker compose up -d homer` (the file is mounted read-only, Homer reads it at startup).
