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

## Technical Notes

- `pipelineJob` in Job DSL does **not** support `publishers { downstreamParameterized }` - use Jenkinsfile orchestration instead
- Job DSL `targets()` only accepts relative paths (Ant GLOB pattern)
- Local git repos require `-Dhudson.plugins.git.GitSCM.ALLOW_LOCAL_CHECKOUT=true`
