#!/bin/bash
# Jenkins API helper script
# Job paths use slash separators (e.g., mobile-app/trigger/main) which are
# automatically converted to Jenkins /job/ paths.

JENKINS_URL="${JENKINS_URL:-http://localhost:8080}"
JENKINS_USER="${JENKINS_USER:-admin}"
JENKINS_PASS="${JENKINS_PASS:-admin}"

COOKIE_JAR="/tmp/jenkins-cookies.txt"

# Convert slash-separated path to Jenkins /job/ path
# e.g., "mobile-app/trigger/main" -> "mobile-app/job/trigger/job/main"
to_job_path() {
    echo "$1" | sed 's|/|/job/|g'
}

get_crumb() {
    curl -s -c "$COOKIE_JAR" -u "$JENKINS_USER:$JENKINS_PASS" \
        "$JENKINS_URL/crumbIssuer/api/json" | \
        python3 -c "import sys,json; d=json.load(sys.stdin); print(d['crumb'])"
}

api_get() {
    curl -s -u "$JENKINS_USER:$JENKINS_PASS" "$JENKINS_URL$1"
}

api_post() {
    local crumb=$(get_crumb)
    curl -s -b "$COOKIE_JAR" -u "$JENKINS_USER:$JENKINS_PASS" \
        -H "Jenkins-Crumb: $crumb" -X POST "$JENKINS_URL$1" -w "\n"
}

case "$1" in
    build)
        if [ -z "$2" ]; then
            echo "Usage: $0 build <job-path> [param=value ...]"
            echo "Example: $0 build mobile-app/trigger/main CI_BRANCH=main"
            exit 1
        fi
        JOB_PATH=$(to_job_path "$2")
        shift 2
        if [ $# -gt 0 ]; then
            PARAMS=""
            for p in "$@"; do
                PARAMS="${PARAMS}&${p}"
            done
            echo "Triggering build for $JOB_PATH..."
            api_post "/job/$JOB_PATH/buildWithParameters?${PARAMS#&}"
        else
            echo "Triggering build for $JOB_PATH..."
            api_post "/job/$JOB_PATH/build"
        fi
        echo "Build triggered"
        ;;
    log)
        if [ -z "$2" ]; then
            echo "Usage: $0 log <job-path> [build#]"
            exit 1
        fi
        BUILD="${3:-lastBuild}"
        api_get "/job/$(to_job_path "$2")/$BUILD/consoleText"
        ;;
    status)
        if [ -z "$2" ]; then
            echo "Usage: $0 status <job-path>"
            exit 1
        fi
        api_get "/job/$(to_job_path "$2")/api/json?tree=name,color,lastBuild%5Bnumber,result%5D" | \
            python3 -c "import sys,json; d=json.load(sys.stdin); lb=d.get('lastBuild',{}); print(f\"Job: {d['name']}\nStatus: {d['color']}\nLast Build: #{lb.get('number','N/A')} - {lb.get('result','N/A')}\")"
        ;;
    jobs)
        # List jobs, optionally under a folder path
        if [ -n "$2" ]; then
            PREFIX="/job/$(to_job_path "$2")"
        else
            PREFIX=""
        fi
        api_get "$PREFIX/api/json?tree=jobs%5Bname,color%5D" | \
            python3 -c "import sys,json; d=json.load(sys.stdin); [print(f\"  {j['name']:30s} {j.get('color','')}\") for j in d.get('jobs',[])]"
        ;;
    scan)
        if [ -z "$2" ]; then
            echo "Usage: $0 scan <multibranch-job-path>"
            echo "Example: $0 scan mobile-app/trigger"
            exit 1
        fi
        JOB_PATH=$(to_job_path "$2")
        echo "Scanning $JOB_PATH..."
        api_post "/job/$JOB_PATH/build"
        echo "Scan triggered"
        ;;
    stop)
        if [ -z "$2" ]; then
            echo "Usage: $0 stop <job-path> [build#]"
            echo "Example: $0 stop mobile-app/trigger/main 5"
            exit 1
        fi
        BUILD="${3:-lastBuild}"
        JOB_PATH=$(to_job_path "$2")
        echo "Stopping $JOB_PATH #$BUILD..."
        api_post "/job/$JOB_PATH/$BUILD/stop"
        echo "Stop requested"
        ;;
    *)
        echo "Jenkins API Helper"
        echo "Usage: $0 <command> [args]"
        echo ""
        echo "Commands:"
        echo "  build <path> [params]    Trigger a build"
        echo "  log <path> [build#]      Get console log (default: lastBuild)"
        echo "  status <path>            Get job status"
        echo "  jobs [folder-path]       List jobs (optionally in a folder)"
        echo "  scan <path>              Trigger multibranch index scan"
        echo "  stop <path> [build#]     Stop a running build"
        echo ""
        echo "Job paths use slash separators (auto-converted to /job/ paths):"
        echo "  $0 build mobile-app/trigger/main CI_BRANCH=main"
        echo "  $0 log mobile-app-support/omnibus 5"
        echo "  $0 status mobile-app/trigger/main"
        echo "  $0 jobs mobile-app"
        echo "  $0 scan mobile-app/trigger"
        echo "  $0 stop mobile-app/trigger/main 3"
        ;;
esac
