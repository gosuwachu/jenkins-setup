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
| dev2 | dev2 | pipeline |

## Pipeline Architecture

**Orchestrator + Commit Status API (GitHub)**

- **Folder:** `pipeline`
- **GitHub repo:** [jenkinsfiles-test-app](https://github.com/gosuwachu/jenkinsfiles-test-app)
- **How it works:** Multibranch orchestrator discovers branches/PRs, triggers child `pipelineJob`s; each child job publishes its own GitHub commit status (not Checks API)
- **Pros:** Each child job owns its status reporting, `target_url` links to child job build page, individually re-triggerable from Jenkins
- **Cons:** No "Re-run" button from GitHub (commit statuses don't support it), no rich check details

Child jobs publish their own commit statuses via `POST /repos/{owner}/{repo}/statuses/{sha}`. Each child job can be individually re-triggered from Jenkins UI. The status `target_url` links directly to the child job's build page.

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

**Companion repo:** [jenkinsfiles-test-app](https://github.com/gosuwachu/jenkinsfiles-test-app) — contains Jenkinsfiles in `ci/` for the multibranch orchestrator and child jobs.

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
./scripts/jenkins-api.sh build pipeline/job/trigger

# Get console log (default: lastBuild)
./scripts/jenkins-api.sh log pipeline/job/ios-build
./scripts/jenkins-api.sh log pipeline/job/ios-build 5

# Get job status
./scripts/jenkins-api.sh status pipeline/job/trigger
```

**Note:** Job paths use `/job/` between folder and job name (e.g., `folder/job/jobname`).

## Modifying Jobs

Edit `jobs/pipeline.groovy` then run the **seed-job** in Jenkins:
- http://localhost:8080/job/seed-job/ → Build Now

For Jenkinsfile changes, just re-run the job (it pulls from the companion repo).

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

**GitHub App:** `jenkinsfiles-test-github-app` (App ID in `.env`)

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

## Troubleshooting

**Permission warnings about "ambiguous entries"** — Use explicit `USER:` or `GROUP:` prefixes in CASC, or use `userPermissions()`/`groupPermissions()` in Job DSL.

**Jobs not visible to users** — Ensure folder has `hudson.model.Item.Discover` permission for the user (in addition to `Item.Read`).

**New Job DSL not taking effect after `docker-compose build`** — The `jenkins_home` volume persists old files. Either `docker cp` the updated files into the running container, or reset the volume with `docker-compose down -v && docker-compose up -d`.
