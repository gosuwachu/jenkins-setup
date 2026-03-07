# Jenkins Test Environment

A Docker-based Jenkins test environment with a multibranch orchestrator pipeline that publishes GitHub commit statuses.

## Quick Start

```bash
./scripts/start.sh
```

Access at http://localhost:8080

**Users:**
| User | Password | Access |
|------|----------|--------|
| admin | admin | Full administrator |
| dev2 | dev2 | mobile-app |

## Pipeline Architecture

**Orchestrator + Commit Status API (GitHub)**

- **Folder:** `mobile-app`
- **GitHub repo:** [mobile-app](https://github.com/gosuwachu/mobile-app)
- **CI repo:** [mobile-app-ci](https://github.com/gosuwachu/mobile-app-ci) — child Jenkinsfiles (CI step definitions)
- **How it works:** Multibranch orchestrator discovers branches/PRs in the app repo. A thin stub `ci/trigger.Jenkinsfile` in the app repo loads the orchestrator logic from the CI repo via a Jenkins Shared Library (`vars/triggerPipeline.groovy`), using an inline `library` retriever (no pre-registration needed). The orchestrator triggers the omnibus `pipelineJob` with `JENKINSFILE` (path to Jenkinsfile in CI repo), `COMMIT_SHA` (pinned app repo commit), `CHANGE_ID` (PR number), and `CI_BRANCH` (CI repo branch, defaults to `main`) parameters; each child Jenkinsfile checks out the exact commit and publishes its own GitHub commit status (not Checks API)
- **Pros:** Each child job owns its status reporting, `target_url` links to child job build page, individually re-triggerable from Jenkins
- **Cons:** No "Re-run" button from GitHub (commit statuses don't support it), no rich check details

Child jobs publish their own commit statuses via `POST /repos/{owner}/{repo}/statuses/{sha}`. The orchestrator passes `COMMIT_SHA` so all child jobs checkout and report on the exact same commit, avoiding race conditions from branch updates. Each child job can be individually re-triggered from Jenkins UI. The status `target_url` links directly to the child job's build page.

### Comment-Triggered Jobs

**iOS UI Tests** (`mobile-app/ios-ui-tests`) — triggered by commenting `run-ios-ui-tests` on a PR.

- Uses the **Generic Webhook Trigger** plugin to receive GitHub `issue_comment` webhook events
- Webhook URL: `https://<ngrok-url>/generic-webhook-trigger/invoke?token=ios-ui-tests-trigger`
- Resolves the PR branch and SHA via GitHub API (the `issue_comment` payload doesn't include branch info)
- Verifies the commenter is a repo collaborator before running
- Publishes `ci/ios-ui-tests` commit status on the PR head SHA
- Can also be triggered manually from Jenkins UI by setting `CHANGE_ID` parameter

**GitHub webhook setup for comment triggers:**
1. In GitHub repo Settings > Webhooks > Add webhook (separate from the push/PR webhook)
2. Payload URL: `https://<ngrok-url>/generic-webhook-trigger/invoke?token=ios-ui-tests-trigger`
3. Content type: `application/json`
4. Events: Select only "Issue comments"

## Project Structure

```
├── jobs/
│   └── pipeline.groovy            # Job DSL (pipeline + seed job)
├── casc/
│   └── jenkins.yaml               # Jenkins Configuration as Code
├── init.groovy.d/
│   └── create-github-app-credential.groovy  # GitHub App credential setup
├── Dockerfile
├── docker-compose.yml
├── plugins.txt
├── .env                           # GitHub + ngrok credentials (gitignored)
├── github-app-key.pem             # GitHub App private key (gitignored)
└── scripts/
    ├── start.sh
    └── jenkins-api.sh             # API helper script
```

**Companion repos:**
- [mobile-app](https://github.com/gosuwachu/mobile-app) — app repo, contains `ci/trigger.Jenkinsfile` (thin stub that loads shared library from CI repo)
    - There is a clone of this repo here: /home/piotr/src/jenkins/mobile-app (you can use it to make changes)
- [mobile-app-ci](https://github.com/gosuwachu/mobile-app-ci) — CI repo, contains orchestrator (`vars/triggerPipeline.groovy` shared library) and child Jenkinsfiles in `ci/ios/` and `ci/android/` (step definitions)
    - There is a clone of this repo here: /home/piotr/src/jenkins/mobile-app-ci (you can use it to make changes)

## Common Commands

```bash
# Start Jenkins
./scripts/start.sh

# Stop Jenkins
docker-compose down

# View logs
docker-compose logs -f

# Reset Jenkins (clear all data)
docker-compose down -v && docker-compose up -d
```

## Jenkins API Helper

Use `scripts/jenkins-api.sh` for API interactions (handles crumb authentication automatically):

```bash
# Trigger a build
./scripts/jenkins-api.sh build mobile-app/job/trigger

# Get console log (default: lastBuild)
./scripts/jenkins-api.sh log mobile-app/job/ios-build
./scripts/jenkins-api.sh log mobile-app/job/ios-build 5

# Get job status
./scripts/jenkins-api.sh status mobile-app/job/trigger
```

**Note:** Job paths use `/job/` between folder and job name (e.g., `folder/job/jobname`).

## Modifying Jobs

Edit `jobs/pipeline.groovy` then run the **seed-job** in Jenkins:
- http://localhost:8080/job/seed-job/ → Build Now

For orchestrator changes, edit `vars/triggerPipeline.groovy` in the CI repo and push — the stub in the app repo loads it dynamically via shared library. For child Jenkinsfile changes, also push to the CI repo (`mobile-app-ci`) and re-run — the omnibus job pulls from the CI repo at `main`.

Only rebuild Docker when changing `Dockerfile`, `plugins.txt`, or `casc/jenkins.yaml`:
```bash
docker-compose build && docker-compose up -d
```

## Per-Project Permissions

This environment uses **Project-based Matrix Authorization Strategy** (via `matrix-auth` plugin) to restrict folder visibility per user.

**Configuration:**
- Global permissions in `casc/jenkins.yaml` (Overall/Read for authenticated users)
- Folder permissions in `jobs/pipeline.groovy` using Job DSL

**Job DSL syntax for folder permissions (matrix-auth > 3.0):**
```groovy
folder('my-folder') {
    authorization {
        userPermissions('username', [
            'hudson.model.Item.Discover',
            'hudson.model.Item.Read',
            'hudson.model.Item.Build',
            'hudson.model.Item.Workspace'
        ])
    }
}
```

**Available methods:**
- `userPermissions(userName, permissionsList)` - grant multiple permissions to a user
- `userPermissionAll(userName)` - grant all permissions to a user
- `groupPermissions(groupName, permissionsList)` - grant permissions to a group

## GitHub Integration

The multibranch pipeline discovers branches/PRs from GitHub.

**Setup:**
1. Create a GitHub PAT with `repo` and `admin:repo_hook` scopes
2. Create a GitHub App (see "GitHub App" section below)
3. Add credentials to `.env`:
   ```
   GITHUB_USERNAME=gosuwachu
   GITHUB_PAT=ghp_xxxx
   GITHUB_APP_ID=<app-id>
   ```
4. Place the GitHub App private key as `github-app-key.pem` (PKCS#8 format, gitignored)
5. Rebuild: `docker-compose build && docker-compose up -d`
6. Run seed-job to create the multibranch jobs

**Webhook setup (for instant PR triggers):**
1. Add your ngrok auth token to `.env`: `NGROK_AUTHTOKEN=<your-token>`
2. ngrok starts automatically with `docker-compose up -d`
3. Get the public URL: `curl -s http://localhost:4040/api/tunnels | python3 -c "import sys,json; print(json.load(sys.stdin)['tunnels'][0]['public_url'])"`
4. In GitHub repo Settings > Webhooks > Add webhook:
   - Payload URL: `https://<ngrok-url>/github-webhook/` (trailing slash required)
   - Content type: `application/json`
   - Events: Push + Pull requests

The ngrok dashboard is available at http://localhost:4040.

Without a webhook, Jenkins polls GitHub every 5 minutes via `periodicFolderTrigger`.

## GitHub App

The GitHub App credential is used by child Jenkinsfiles (via `withCredentials`) to publish commit statuses. The multibranch orchestrator and child jobs use `github-pat` for SCM operations to prevent the github-checks plugin from auto-publishing checks.

**GitHub App:** `jenkins-setup-github-app` (App ID in `.env`)

**Required GitHub App permissions:**
- Commit statuses: Read & Write (for commit status publishing)
- Contents: Read (for SCM checkout)
- Pull requests: Read (for PR discovery)
- Metadata: Read

**Key files:**
| File | Purpose |
|------|---------|
| `github-app-key.pem` | GitHub App private key (PKCS#8, gitignored) |
| `init.groovy.d/create-github-app-credential.groovy` | Creates `github-app` credential at startup |

**PEM key format:** Must be PKCS#8 (`BEGIN PRIVATE KEY`). Convert from PKCS#1 if needed:
```bash
openssl pkcs8 -topk8 -inform PEM -outform PEM -nocrypt -in key.pem -out github-app-key.pem
```

## Fork PR Security

The multibranch pipeline discovers fork PRs with `TrustContributors` trust strategy:
- **Collaborator forks:** CI runs using their Jenkinsfile (trusted)
- **Non-collaborator PRs:** Jenkinsfile is read from the target branch. CI is blocked unless the PR has an approved review from a collaborator. Without approval, the build is set to `NOT_BUILT`

This two-layer approach ensures non-collaborators cannot run CI or inject malicious pipeline code.

## Job DSL Notes

- Job DSL `targets()` only accepts relative paths (Ant GLOB), not absolute paths
- The seed job copies DSL files to workspace before processing
- `pipelineJob` uses `cpsScm` to read Jenkinsfiles from SCM
- **`pipelineJob` does NOT support `publishers { downstreamParameterized }`** — use Jenkinsfile orchestration instead

**Job DSL API Reference:** http://localhost:8080/plugin/job-dsl/api-viewer/index.html (when Jenkins is running)

## After Making Changes

Always follow this workflow after completing code changes:
1. **Commit** changes in all affected repos
2. **Push** companion repos (mobile-app, mobile-app-ci) since Jenkins pulls from GitHub
3. **Deploy** to Jenkins:
   - If only `jobs/pipeline.groovy` changed: `docker cp jobs/pipeline.groovy jenkins-test:/var/jenkins_home/jobs-dsl/pipeline.groovy` then `./scripts/jenkins-api.sh build seed-job`
   - If `Dockerfile`, `plugins.txt`, or `casc/jenkins.yaml` changed: `docker-compose build && docker-compose up -d`
4. **Test** by triggering a build: `./scripts/jenkins-api.sh build mobile-app/job/trigger/job/main CI_BRANCH=main`
5. **Verify** results via `./scripts/jenkins-api.sh status` and `./scripts/jenkins-api.sh log`

## Troubleshooting

**Permission warnings about "ambiguous entries"** — Use explicit `USER:` or `GROUP:` prefixes in CASC, or use `userPermissions()`/`groupPermissions()` in Job DSL.

**Jobs not visible to users** — Ensure folder has `hudson.model.Item.Discover` permission for the user (in addition to `Item.Read`).

**New Job DSL not taking effect after `docker-compose build`** — The `jenkins_home` volume persists old files. Either `docker cp` the updated files into the running container, or reset the volume with `docker-compose down -v && docker-compose up -d`.

**ios-ui-tests not triggering from PR comment** — Ensure the GitHub webhook is configured for `issue_comment` events pointing to `/generic-webhook-trigger/invoke?token=ios-ui-tests-trigger` (this is a separate webhook from the push/PR one).
