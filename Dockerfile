FROM jenkins/jenkins:lts-jdk17

# Skip setup wizard
ENV JAVA_OPTS="-Djenkins.install.runSetupWizard=false -Dhudson.plugins.git.GitSCM.ALLOW_LOCAL_CHECKOUT=true"

# Install plugins
COPY plugins.txt /usr/share/jenkins/ref/plugins.txt
RUN jenkins-plugin-cli --plugin-file /usr/share/jenkins/ref/plugins.txt

# Copy Configuration as Code files
COPY casc/ /var/jenkins_home/casc_configs/
ENV CASC_JENKINS_CONFIG=/var/jenkins_home/casc_configs/

# Copy init scripts (run at Jenkins startup)
COPY init.groovy.d/ /var/jenkins_home/init.groovy.d/

# Copy Job DSL scripts
COPY jobs/ /var/jenkins_home/jobs-dsl/

# Set proper permissions
USER root
RUN chown -R jenkins:jenkins /var/jenkins_home/jobs-dsl/
USER jenkins
