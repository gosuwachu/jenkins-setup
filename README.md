# Jenkins Pipeline Architecture Comparison

A Docker-based Jenkins environment demonstrating different approaches to pipeline orchestration.

## Quick Start

```bash
docker-compose up -d
```

Open http://localhost:8080 and login with `admin` / `admin`

## The Problem

When a Jenkins pipeline fails mid-way, you often want to:
- **Re-run just the failed stage** without starting from scratch
- **Re-trigger individual jobs** (e.g., just iOS deploy, not the whole pipeline)

---

## Project Structure

```
├── jobs/
│   └── pipeline.groovy         # Job DSL definitions for all options
├── casc/
│   └── jenkins.yaml            # Jenkins Configuration as Code
├── Dockerfile
├── docker-compose.yml
└── plugins.txt
```

## Common Commands

```bash
# Start Jenkins
docker-compose up -d

# View logs
docker-compose logs -f

# Stop Jenkins
docker-compose down

# Full reset (clear all data)
docker-compose down -v
docker-compose up -d

# Rebuild after changing Dockerfile/plugins
docker-compose build --no-cache
docker-compose up -d
```

## Modifying Jobs

**Job DSL changes:** Edit `jobs/pipeline.groovy`, then run the seed-job:
http://localhost:8080/job/seed-job/ → Build Now

**Jenkinsfile changes:** Just commit and re-run the pipeline (it pulls from the repo).

## Companion Repos

- **[mobile-app](https://github.com/gosuwachu/mobile-app)** — app repo, contains `ci/trigger.Jenkinsfile` (orchestrator)
- **[mobile-app-ci](https://github.com/gosuwachu/mobile-app-ci)** — CI repo, child Jenkinsfiles:

```
ci/
├── ios/
│   ├── ios-build.Jenkinsfile
│   ├── ios-deploy.Jenkinsfile
│   ├── ios-linter.Jenkinsfile
│   ├── ios-ui-tests.Jenkinsfile
│   └── ios-unit-tests.Jenkinsfile
└── android/
    ├── android-build.Jenkinsfile
    ├── android-deploy.Jenkinsfile
    ├── android-linter.Jenkinsfile
    └── android-unit-tests.Jenkinsfile
```

## Technical Notes

- `pipelineJob` in Job DSL does **not** support `publishers { downstreamParameterized }` - use Jenkinsfile orchestration instead
- Job DSL `targets()` only accepts relative paths (Ant GLOB pattern)
- Local git repos require `-Dhudson.plugins.git.GitSCM.ALLOW_LOCAL_CHECKOUT=true`

## Design Decisions

### Why jobs are defined as Jenkinsfiles?
The alternative is to pass a NODE_LABEL parameter and a path to the shell script, but this will mean that we don't have control over which jobs have access to which credentials. Also, for jobs like iOS UI tests, Jenkinsfile gives us possibly to dynamically parallelize running the UI tests on multiple agents.

### Trigger job as a shared library
Trigger job is loaded as a shared library so that we can see a visualization of the checks that are going to run. We can also see this way which checks have failed in Jenkins for each change without implementing custom UI. 
