pipeline {
	agent none
	options {
		disableConcurrentBuilds()
		disableResume()
		skipStagesAfterUnstable()
	}
	environment {
		DEPLOY_SCRIPT = '.jenkins/deploy.ps1'
		DEPLOY_BINARY = '.jenkins/results/zerotier-one.exe'
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
				CMAKE_BUILD_TYPE = 'Release'
				CMAKE_GENERATOR = 'Ninja'
				CMAKE_PREFIX_PATH = 'ext/opentelemetry-cpp-api-only'
				CMAKE_TOOLCHAIN_FILE = 'C:/vcpkg/scripts/buildsystems/vcpkg.cmake'
				VCPKG_DEFAULT_TRIPLET = 'x64-windows-static'
				VCPKG_DEFAULT_BINARY_CACHE = "${WORKSPACE}/.jenkins/cache/vcpkg"
				CARGO_HOME = "${WORKSPACE}/.jenkins/cache/cargo"
			}
			stages {
				stage('Build') {
					steps {
						exec 'cmake -E make_directory .jenkins/results .jenkins/cache/cargo .jenkins/cache/vcpkg'
						exec 'cmake -S . -B .jenkins/results'
						exec 'cmake --build .jenkins/results --parallel'
					}
					post {
						success {
							stash name: 'zerotier-one', includes: "$DEPLOY_SCRIPT, $DEPLOY_BINARY"
							archiveArtifacts artifacts: DEPLOY_BINARY
						}
					}
				}
				stage('Test') {
					steps {
						writeFile file: '.jenkins/results/CTestResults.xml', text: '<testsuites tests="0" failures="0" errors="0"/>'
						exec "ctest --test-dir .jenkins/results -C $CMAKE_BUILD_TYPE --output-on-failure --output-junit CTestResults.xml"
					}
					post {
						always {
							junit testResults: '.jenkins/results/*.xml', allowEmptyResults: true
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
				
				unstash 'zerotier-one'
				
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
							sshCommand remote: remote, command: "powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $DEPLOY_SCRIPT"
						}
					}
				}
			}
		}
	}
}
