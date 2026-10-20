# GitLab runner

The `gitlab-runner` container runs CI jobs in sibling containers through the mounted docker socket. It starts unregistered: register it once per project (or once at instance level as root).

1. Project → Settings → CI/CD → Runners → New project runner. Tick "Run untagged jobs", create, and copy the `glrt-…` token.
2. Register:
   ```bash
   docker exec -it homer-gitlab-runner gitlab-runner register \
     --non-interactive \
     --url http://gitlab:8929 \
     --clone-url http://gitlab:8929 \
     --token <glrt-token> \
     --description homer-runner \
     --executor docker \
     --docker-image docker:27 \
     --docker-network-mode homer-network
   ```
3. Check: `docker exec homer-gitlab-runner gitlab-runner list`, and the runner shows as online on the project's Runners page.

Why the flags:

- `--url http://gitlab:8929`: the runner reaches GitLab over the compose network, not `localhost`.
- `--clone-url http://gitlab:8929`: GitLab tells jobs to clone from its `external_url` (`http://localhost:8929`), which inside a job container is the container itself. This overrides it.
- `--docker-network-mode homer-network`: job containers join the compose network (named in `docker-compose.yml`) so they can reach `gitlab`.

The docker socket mount gives the runner full control of your docker daemon: fine for local use, never expose this setup.

Inspect the runner configuration with `docker cp homer-gitlab-runner:/etc/gitlab-runner/config.toml ./config.toml` (gitignored, it contains runner tokens).
