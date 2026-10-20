"use strict";
// Pre-"compiled" CommonJS module
// Mounted at /app/dist/plugins/release/simpleReleaseManager.js (see docker-compose.yml)
// and referenced by name "simpleReleaseManager" in homer-config/projects.json.
Object.defineProperty(exports, "__esModule", { value: true });

const BUILD_JOB_NAME = "build_image";

// Gate: same idea as defaultReleaseManager, but matching a single job name
// instead of a hardcoded list. Called before Homer starts a release, polling
// every 30s (see waitForReadinessAndStartRelease.ts) until it returns true
// or a 45 minute timeout is hit.
async function isReadyToRelease(release, mainBranchPipelineId, options) {
  const { projectId } = release;
  const { fetchPipelineJobs } = options.gitlab;

  const jobs = await fetchPipelineJobs(projectId, mainBranchPipelineId);
  const buildJob = jobs.find((job) => job.name === BUILD_JOB_NAME);

  options.logger.info(
    { projectId, mainBranchPipelineId, buildJob },
    "[simpleReleaseManager] isReadyToRelease check",
  );

  return buildJob?.status === "success";
}

// Progression: only called by deploymentHookHandler.ts, which itself is only
// reached when GitLab sends a "Deployment event" webhook to
// POST /api/v1/homer/gitlab. If you haven't wired that webhook up in your
// local GitLab CE project, this simply never gets invoked — which is fine
// for testing "isReadyToRelease" + release creation on their own.
//
// To exercise this manually without configuring real GitLab environments/
// webhooks, POST a fake payload matching GitlabDeploymentHook, e.g.:
//
//   curl -X POST http://localhost:3000/api/v1/homer/gitlab \
//     -H "Content-Type: application/json" \
//     -H "X-Gitlab-Event: Deployment Hook" \
//     -H "X-Gitlab-Token: $GITLAB_SECRET" \
//     -d '{
//       "object_kind": "deployment",
//       "status": "success",
//       "environment": "production",
//       "deployment_id": 1,
//       "status_changed_at": "2026-08-19T00:00:00Z",
//       "project": { "id": <projectId> }
//     }'
//
// (fetchDeploymentById is called with the deployment_id first, so GitLab
// must actually have a deployment record with that id for the project.)
async function getReleaseStateUpdate(_release, deploymentHook, options) {
  if (deploymentHook === undefined) {
    return [];
  }

  const { environment, status } = deploymentHook;

  options?.logger?.info(
    { environment, status },
    "[simpleReleaseManager] getReleaseStateUpdate",
  );

  // Simplified vs. defaultReleaseManager: no separate "monitoring" phase,
  // success goes straight to "completed" for every environment.
  switch (status) {
    case "failed":
      return [{ deploymentState: "failed", environment }];
    case "running":
      return [{ deploymentState: "deploying", environment }];
    case "success":
      return [{ deploymentState: "completed", environment }];
    default:
      throw new Error(`Unhandled deployment status: ${status}`);
  }
}

exports.default = {
  isReadyToRelease,
  getReleaseStateUpdate,
};
