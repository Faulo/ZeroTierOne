pipeline {
	agent none
	options {
		disableConcurrentBuilds()
		disableResume()
		skipStagesAfterUnstable()
	}
	environment {
		DEPLOY_SCRIPT = '.jenkins/deploy.ps1'
		DEPLOY_BINARY = '.jenkins/artifacts/zerotier-one_x64.exe'
	}
	stages {
		stage('Prepare') {
			agent {
				dockerfile {
					filename 'Dockerfile'
					dir '.jenkins'
					label 'windows && docker'
				}
			}
			environment {
				BUILD_CONFIGURATION = 'Release'
				BUILD_PLATFORM = 'x64'
				CARGO_HOME = "${WORKSPACE}/.jenkins/cache/cargo"
			}
			stages {
				stage('Build') {
					steps {
						exec 'New-Item -ItemType Directory -Force .jenkins/artifacts, .jenkins/cache/cargo, .jenkins/reports | Out-Null'
						exec 'msbuild.exe windows/ZeroTierOne.sln -m -t:ZeroTierOne -p:Configuration=$env:BUILD_CONFIGURATION -p:Platform=$env:BUILD_PLATFORM -p:VCToolsVersion=$env:MSVC_TOOLSET_VERSION -verbosity:minimal'
						exec 'Copy-Item windows/Build/x64/Release/zerotier-one_x64.exe $env:DEPLOY_BINARY'
					}
					post {
						success {
							archiveArtifacts artifacts: DEPLOY_BINARY
							stash name: 'deploy', includes: "$DEPLOY_SCRIPT, $DEPLOY_BINARY"
						}
					}
				}
				stage('Test') {
					steps {
						exec '& $env:DEPLOY_BINARY -v'
						writeFile file: '.jenkins/reports/smoke.xml', text: '<testsuites tests="1"><testsuite name="ZeroTierOne" tests="1"><testcase name="version"/></testsuite></testsuites>'
					}
					post {
						always {
							junit testResults: '.jenkins/reports/*.xml', allowEmptyResults: true
						}
					}
				}
			}
		}
		stage('Deploy') {
			agent {
				label 'Garl'
			}
			options {
				skipDefaultCheckout()
			}
			environment {
				SSH_CREDENTIALS = 'Strayfarer-Daniel'
			}
			steps {
				cleanWs()

				unstash 'deploy'

				script {
					def targets = ['popo']

					for (def target in targets) {
						def ip = execStdout "getent ahostsv4 $target | awk '\$1 ~ /^192.168./ { print \$1; exit }'"

						echo "IP of '$target' is: $ip"

						def remote = [
							name: target,
							host: ip,
							allowAnyHosts: true
						]

						withCredentials([sshUserPrivateKey(credentialsId: SSH_CREDENTIALS, keyFileVariable: 'SSH_KEY_FILE', usernameVariable: 'SSH_USER')]) {
							remote.user = SSH_USER
							remote.identityFile = SSH_KEY_FILE

							sshPut remote: remote, from: DEPLOY_SCRIPT, into: DEPLOY_SCRIPT
							sshPut remote: remote, from: DEPLOY_BINARY, into: DEPLOY_BINARY
							sshCommand remote: remote, command: "pwsh.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $DEPLOY_SCRIPT -Binary $DEPLOY_BINARY"
						}
					}
				}
			}
		}
	}
}
