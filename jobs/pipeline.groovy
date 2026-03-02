// ============================================
// Mobile CI/CD Pipeline - Job DSL Script
// Option 4B-MB: Orchestrator + Commit Status API
// ============================================

def githubRepoOwner = 'gosuwachu'
def githubRepoName = 'jenkinsfiles-test-app'
def githubRepoUrl = "https://github.com/${githubRepoOwner}/${githubRepoName}.git"
def githubCredentialsId = 'github-app'

// ============================================
// OPTION 4B-MB: Orchestrator + Pipeline Jobs with Commit Status API (GitHub)
// Folder: pipeline-4b-mb
// Child jobs publish their own GitHub commit statuses (not Checks API)
// ============================================

def folder4bmb = 'pipeline-4b-mb'

folder(folder4bmb) {
    description('Option 4B-MB: Orchestrator multibranch + child jobs with commit status API (GitHub)')
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
multibranchPipelineJob("${folder4bmb}/trigger") {
    displayName('Pipeline Trigger (Multibranch)')
    description('Orchestrator - discovers branches/PRs, triggers child jobs (commit status variant)')

    branchSources {
        github {
            id('pipeline-4b-mb-github')
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
    pipelineJob("${folder4bmb}/${jobName}") {
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
