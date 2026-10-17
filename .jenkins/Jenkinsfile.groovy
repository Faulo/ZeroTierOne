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
	environment {
		CMAKE_BUILD_TYPE = 'Release'
		CMAKE_GENERATOR = 'Ninja'
		CMAKE_PREFIX_PATH = 'ext/opentelemetry-cpp-api-only'
		CMAKE_TOOLCHAIN_FILE = 'C:/vcpkg/scripts/buildsystems/vcpkg.cmake'
		VCPKG_DEFAULT_TRIPLET = 'x64-windows-static'
	}
	stages {
		stage('Build') {
			steps {
				dir('.jenkins/result') {
					deleteDir()
				}
				exec 'cmake -S . -B .jenkins/result'
				exec 'cmake --build .jenkins/result --parallel'
			}
			post {
				success {
					archiveArtifacts artifacts: 'result/*.exe'
				}
			}
		}
		stage('Test') {
			steps {
				exec 'ctest --test-dir .jenkins/result -C $CMAKE_BUILD_TYPE --output-on-failure --output-junit .jenkins/result/CTestResults.xml'
			}
			post {
				always {
					junit testResults: '.jenkins/result/*.xml'
				}
			}
		}
	}
}
