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
			post {
				success {
					archiveArtifacts artifacts: '.jenkins/artifacts/**.exe'
				}
			}
		}
		stage('Test') {
			steps {
				powershell '& .\\.jenkins\\test.ps1'
			}
			post {
				always {
					junit testResults: '.jenkins/reports/**.xml'
				}
			}
		}
	}
}
