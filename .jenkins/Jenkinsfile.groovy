pipeline {
	agent {
		dockerfile {
			filename 'Dockerfile'
			dir '.jenkins'
			label 'windows && docker'
		}
	}
	options {
		disableConcurrentBuilds()
		disableResume()
	}
	stages {
		stage('Build') {
			steps {
				powershell '& .\\.jenkins\\build.ps1'
			}
		}
		stage('Test') {
			steps {
				powershell '& .\\.jenkins\\test.ps1'
			}
			post {
				always {
					junit testResults: '.jenkins/artifacts/*TestResults.xml'
				}
			}
		}
	}
	post {
		always {
			archiveArtifacts artifacts: '.jenkins/artifacts/**', allowEmptyArchive: true, fingerprint: true
		}
	}
}
