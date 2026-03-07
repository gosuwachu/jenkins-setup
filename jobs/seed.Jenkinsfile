pipeline {
    agent any
    stages {
        stage('Seed') {
            steps {
                jobDsl targets: 'jobs/pipeline.groovy',
                       removedJobAction: 'DELETE',
                       removedViewAction: 'DELETE',
                       lookupStrategy: 'SEED_JOB',
                       failOnMissingPlugin: true
            }
        }
    }
}
