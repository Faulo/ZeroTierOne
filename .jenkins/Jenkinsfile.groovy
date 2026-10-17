pipeline {
	agent none
	options {
		disableConcurrentBuilds()
		disableResume()
		skipStagesAfterUnstable()
	}
	environment {
		CMAKE_BUILD_TYPE = 'Release'
		CMAKE_GENERATOR = 'Ninja'
		CMAKE_PREFIX_PATH = 'ext/opentelemetry-cpp-api-only'
		CMAKE_TOOLCHAIN_FILE = 'C:/vcpkg/scripts/buildsystems/vcpkg.cmake'
		VCPKG_DEFAULT_TRIPLET = 'x64-windows-static'
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
				CARGO_HOME = "${WORKSPACE}/.jenkins/cache/cargo"
				VCPKG_DEFAULT_BINARY_CACHE = "${WORKSPACE}/.jenkins/cache/vcpkg"
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
							archiveArtifacts artifacts: '.jenkins/results/*.exe'
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
			steps {
				exec 'ping popo'
			}
		}
	}
}
