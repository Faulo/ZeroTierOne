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
		stage('Build and test') {
			steps {
				powershell '& .\\.jenkins\\build.ps1'
			}
		}
	}
	post {
		always {
			junit testResults: '.jenkins/artifacts/TestResults.xml', allowEmptyResults: true
			archiveArtifacts artifacts: '.jenkins/artifacts/**', allowEmptyArchive: true, fingerprint: true
		}
	}
}
