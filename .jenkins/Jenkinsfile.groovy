pipeline {
	agent none
	options {
		disableConcurrentBuilds()
		disableResume()
	}
	environment {
		CMAKE_BUILD_TYPE = 'Release'
		CMAKE_GENERATOR = 'Ninja'
		CMAKE_PREFIX_PATH = 'ext/opentelemetry-cpp-api-only'
		CMAKE_TOOLCHAIN_FILE = 'C:/vcpkg/scripts/buildsystems/vcpkg.cmake'
		VCPKG_DEFAULT_TRIPLET = 'x64-windows-static'
	}
	stages {
		stage('Build and Test') {
			agent {
				dockerfile {
					filename 'Dockerfile'
					dir '.jenkins'
					label 'windows && docker'
				}
			}
			steps {
				stage('Build') {
					steps {
						dir('.jenkins/results') {
							deleteDir()
						}
						exec 'cmake -S . -B .jenkins/results'
						exec 'cmake --build .jenkins/results --parallel'
					}
					post {
						success {
							archiveArtifacts artifacts: 'results/*.exe'
						}
					}
				}
				stage('Test') {
					steps {
						exec 'ctest --test-dir .jenkins/results -C $CMAKE_BUILD_TYPE --output-on-failure --output-junit .jenkins/results/CTestResults.xml'
					}
					post {
						always {
							junit testResults: '.jenkins/results/*.xml'
						}
					}
				}
			}
		}
	}
}
