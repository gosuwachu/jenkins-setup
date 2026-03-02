#!/bin/bash
# Jenkins API helper script
# Usage:
#   ./scripts/jenkins-api.sh build <job-path>        # Trigger a build
#   ./scripts/jenkins-api.sh log <job-path> [build#] # Get console log (default: lastBuild)
#   ./scripts/jenkins-api.sh status <job-path>       # Get job status

JENKINS_URL="${JENKINS_URL:-http://localhost:8080}"
JENKINS_USER="${JENKINS_USER:-admin}"
JENKINS_PASS="${JENKINS_PASS:-admin}"

COOKIE_JAR="/tmp/jenkins-cookies.txt"

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
            echo "Usage: $0 build <job-path>"
            echo "Example: $0 build pipeline-4b-mb/job/trigger"
            exit 1
        fi
        echo "Triggering build for $2..."
        api_post "/job/$2/build"
        echo "Build triggered"
        ;;
    log)
        if [ -z "$2" ]; then
            echo "Usage: $0 log <job-path> [build#]"
            exit 1
        fi
        BUILD="${3:-lastBuild}"
        api_get "/job/$2/$BUILD/consoleText"
        ;;
    status)
        if [ -z "$2" ]; then
            echo "Usage: $0 status <job-path>"
            exit 1
        fi
        api_get "/job/$2/api/json?tree=name,color,lastBuild%5Bnumber,result%5D" | \
            python3 -c "import sys,json; d=json.load(sys.stdin); lb=d.get('lastBuild',{}); print(f\"Job: {d['name']}\nStatus: {d['color']}\nLast Build: #{lb.get('number','N/A')} - {lb.get('result','N/A')}\")"
        ;;
    *)
        echo "Jenkins API Helper"
        echo "Usage: $0 <command> [args]"
        echo ""
        echo "Commands:"
        echo "  build <job-path>         Trigger a build"
        echo "  log <job-path> [build#]  Get console log (default: lastBuild)"
        echo "  status <job-path>        Get job status"
        echo ""
        echo "Examples:"
        echo "  $0 build pipeline-4b-mb/job/trigger"
        echo "  $0 log pipeline-4b-mb/job/ios-build 1"
        echo "  $0 status pipeline-4b-mb/job/trigger"
        ;;
esac
