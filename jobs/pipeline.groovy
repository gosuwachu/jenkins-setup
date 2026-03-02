// ============================================
// Mobile CI/CD Pipeline - Job DSL Script
// Orchestrator + Commit Status API
// ============================================

def githubRepoOwner = 'gosuwachu'
def githubRepoName = 'jenkinsfiles-test-app'
def githubRepoUrl = "https://github.com/${githubRepoOwner}/${githubRepoName}.git"
def githubCredentialsId = 'github-app'

// ============================================
// Orchestrator + Pipeline Jobs with Commit Status API (GitHub)
// Folder: pipeline
// Child jobs publish their own GitHub commit statuses (not Checks API)
// ============================================

def pipelineFolder = 'pipeline'

folder(pipelineFolder) {
    description('Orchestrator multibranch + child jobs with commit status API (GitHub)')
    authorization {
        userPermissions('dev2', [
            'hudson.model.Item.Discover',
            'hudson.model.Item.Read',
            'hudson.model.Item.Build',
            'hudson.model.Item.Workspace'
        ])
    }
}

// Orchestrator - multibranch, discovers branches/PRs
// Uses github-pat (not github-app) to prevent github-checks plugin from auto-publishing checks
multibranchPipelineJob("${pipelineFolder}/trigger") {
    displayName('Pipeline Trigger (Multibranch)')
    description('Orchestrator - discovers branches/PRs, triggers child jobs (commit status variant)')

    branchSources {
        github {
            id('pipeline-github')
            scanCredentialsId('github-pat')
            repoOwner(githubRepoOwner)
            repository(githubRepoName)
        }
    }

    factory {
        workflowBranchProjectFactory {
            scriptPath('ci/trigger.Jenkinsfile')
        }
    }

    orphanedItemStrategy {
        discardOldItems {
            numToKeep(10)
        }
    }

    triggers {
        periodicFolderTrigger {
            interval('5m')
        }
    }

    // All discovery/filter/notification config as traits (old-style properties break when traits exist)
    configure {
        def traits = it / sources / data / 'jenkins.branch.BranchSource' / source / traits
        // Discover branches (strategyId 3 = all branches)
        traits << 'org.jenkinsci.plugins.github__branch__source.BranchDiscoveryTrait' {
            strategyId(3)
        }
        // Discover origin PRs — head revision only (strategyId 2 = current PR revision)
        traits << 'org.jenkinsci.plugins.github__branch__source.OriginPullRequestDiscoveryTrait' {
            strategyId(2)
        }
        // Filter to only main branch and PRs
        traits << 'jenkins.scm.impl.trait.WildcardSCMHeadFilterTrait' {
            includes('main PR-*')
            excludes('')
        }
        // Discover fork PRs — trust collaborators only
        // Collaborator forks: use their Jenkinsfile. Non-collaborators: use target branch Jenkinsfile.
        // The trigger Jenkinsfile also aborts CI for non-collaborators.
        traits << 'org.jenkinsci.plugins.github__branch__source.ForkPullRequestDiscoveryTrait' {
            strategyId(2)
            trust(class: 'org.jenkinsci.plugins.github_branch_source.ForkPullRequestDiscoveryTrait\$TrustContributors')
        }
        // Custom commit status context name
        traits << 'org.jenkinsci.plugins.githubScmTraitNotificationContext.NotificationContextTrait' {
            contextLabel('Jenkins')
            typeSuffix(false)
        }
    }
}

// Child jobs - regular pipelineJobs that publish their own commit statuses
// Uses github-pat (not github-app) for SCM checkout to prevent auto-publishing checks.
// Child Jenkinsfiles still use github-app via withCredentials for the commit status API.
['ios-build', 'ios-deploy', 'android-build', 'android-deploy',
 'ios-unit-tests', 'android-unit-tests', 'ios-linter', 'android-linter'].each { jobName ->
    pipelineJob("${pipelineFolder}/${jobName}") {
        displayName(jobName.split('-').collect { it.capitalize() }.join(' '))
        parameters {
            stringParam('BRANCH_NAME', 'main', 'Branch to build (passed by orchestrator)')
        }
        definition {
            cpsScm {
                scm {
                    git {
                        remote {
                            url(githubRepoUrl)
                            credentials('github-pat')
                        }
                        branches('${BRANCH_NAME}')
                    }
                }
                scriptPath("ci/${jobName}.Jenkinsfile")
            }
        }
    }
}

// iOS UI Tests — standalone, triggered by PR comment "run-ios-ui-tests" via Generic Webhook Trigger
pipelineJob("${pipelineFolder}/ios-ui-tests") {
    displayName('iOS UI Tests (Comment-Triggered)')
    description('Runs iOS UI tests when "run-ios-ui-tests" is commented on a PR')

    parameters {
        stringParam('PR_NUMBER', '', 'Pull request number (set by webhook)')
        stringParam('COMMENT_AUTHOR', '', 'GitHub username of the commenter (set by webhook)')
    }

    triggers {
        genericTrigger {
            genericVariables {
                genericVariable {
                    key('PR_NUMBER')
                    value('$.issue.number')
                    expressionType('JSONPath')
                    regexpFilter('')
                    defaultValue('')
                }
                genericVariable {
                    key('COMMENT_BODY')
                    value('$.comment.body')
                    expressionType('JSONPath')
                    regexpFilter('')
                    defaultValue('')
                }
                genericVariable {
                    key('ACTION')
                    value('$.action')
                    expressionType('JSONPath')
                    regexpFilter('')
                    defaultValue('')
                }
                genericVariable {
                    key('IS_PULL_REQUEST')
                    value('$.issue.pull_request.url')
                    expressionType('JSONPath')
                    regexpFilter('')
                    defaultValue('')
                }
                genericVariable {
                    key('COMMENT_AUTHOR')
                    value('$.comment.user.login')
                    expressionType('JSONPath')
                    regexpFilter('')
                    defaultValue('')
                }
            }
            token('ios-ui-tests-trigger')
            causeString('PR #$PR_NUMBER comment by $COMMENT_AUTHOR: run-ios-ui-tests')
            regexpFilterText('$ACTION $COMMENT_BODY $IS_PULL_REQUEST')
            regexpFilterExpression('^created run-ios-ui-tests https.*$')
            printContributedVariables(true)
            printPostContent(false)
            silentResponse(false)
        }
    }

    definition {
        cpsScm {
            scm {
                git {
                    remote {
                        url(githubRepoUrl)
                        credentials('github-pat')
                    }
                    branches('main')
                }
            }
            scriptPath('ci/ios-ui-tests.Jenkinsfile')
        }
    }
}

// ============================================
// SEED JOB
// ============================================

job('seed-job') {
    displayName('Seed Job')
    description('Regenerates all pipeline jobs from DSL scripts')
    steps {
        shell('cp /var/jenkins_home/jobs-dsl/*.groovy .')
        jobDsl {
            targets('*.groovy')
            removedJobAction('DELETE')
            removedViewAction('DELETE')
            lookupStrategy('SEED_JOB')
            failOnMissingPlugin(true)
        }
    }
}
