# Hubble Compose Review Fixes

## Baseline and Environment

- Repository: `/Users/himanshuverma/opensource/hugegraph`
- Branch: `hubble-compose-addon`
- Baseline: `origin/master` / `c9a646dd820dd331eab97c73c913f9f4a81f4030`
- Current rebased tip: `6888481cf9524bfb8baa8d6756c43319fe543d9d`
- Worktree was clean before initialization.
- Docker validation may use the authorized SSH/Tailscale library endpoint; all
  repository and Git operations remain local for this task.
- Upstream PR: `apache/hugegraph#3149`.

## Active Truth and Authority

1. Latest user instruction and explicit push authorization.
2. Repository `AGENTS.md` and module-local guidance.
3. Current source, Compose files, CI workflow, and existing tests.
4. PR #3149 review comments and their cited dependency/runtime evidence.
5. This file and `.goal-task/hubble-compose-review-fixes/{todo,design}.md`.

## Scope and Gates

Fix the remaining open review findings for PR #3149 while preserving the Hubble
add-on design and rebased master ancestry. The candidate must:

- parse and validate generated/existing credentials safely;
- persist Hubble H2 state at the actual database path and share volumes across
  attach and combined flows;
- avoid false-green auth/image checks and unsafe dotenv execution;
- keep control-plane exposure deliberate and document/configure advertised Server
  addresses;
- make CI assertions cover every Server replica and explicit PD mode;
- provide a Docker-capable combined/attach smoke check when the authorized
  endpoint is available;
- pass targeted YAML/shell/CI checks and relevant repository tests;
- pass exactly 3 independent implementation reviews, fixes and re-review;
- pass exactly one final independent `Design Audit` before completion;
- create a local milestone commit after all gates pass; pushing is explicitly
  excluded so the user can audit the final state first.

## Phase State

1. Initialization: completed.
2. Implementation: completed for the first review-fix batch.
3. Targeted and Docker validation: pending.
4. Three independent implementation reviews: pending.
5. Review fixes and re-review: pending.
6. One-shot Design Audit: pending.
7. Final completion audit and local commit: pending.

## Validation and Review Evidence

- GitHub API confirms PR #3149 is open with review decision `REVIEW_REQUIRED`.
- Remaining review comments are recorded in `todo.md`; previously addressed
  comments are not reopened unless current code disproves the response.
- Local evidence: both Compose files render; README Bash blocks pass `bash -n`;
  `git diff --check` passes; combined jq contract checks pass.
- Remote evidence: `library` over SSH/Tailscale ran the cluster-alone auth
  checks (401 without credentials, 200 with credentials), attached Hubble
  without changing eight cluster container IDs, recreated Hubble through the
  combined flow, and verified both explicit Hubble volumes. Docker Compose
  emitted only the expected cross-project volume-label warnings for the shared
  named volumes; the smoke itself passed.
- First implementation batch changed Compose security/persistence/readiness,
  documentation parsing and deployment guidance, and CI render/smoke coverage.

## Recovery and Stop Rules

- Retry an individual failing item at most three times; record evidence and defer
  only that item while continuing independent work.
- A permission/network gap is `needs input` unless the authorized SSH/Tailscale
  Docker endpoint resolves it.
- Do not mark complete while any review finding, validation gate, or audit is
  unresolved. Stop only if every remaining item is jointly blocked by the same
  verified dependency or safety boundary.

## Next Action

Run the targeted validation suite and the authorized remote Docker smoke test,
then freeze the candidate for independent reviews.
