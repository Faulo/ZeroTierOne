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
						stash name: 'zerotier-one', includes: '.jenkins/results/zerotier-one.exe'
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
				docker {
					image 'alpine/git:latest'
					label 'Garl'
					args '--entrypoint='
				}
			}
			options {
				skipDefaultCheckout()
				timeout(time: 2, unit: 'MINUTES')
			}
			environment {
				POPO_SSH_HOST_KEY_SHA256 = 'SHA256:YvOebKch9c4d13c++p7G39z2LJ0KQfEeVwro3QG7eFU'
			}
			steps {
				unstash 'zerotier-one'
				writeFile file: '.jenkins/deploy.ps1', text: '''
$ErrorActionPreference = 'Stop'

$serviceName = 'ZeroTierOneService'
$target = 'C:\\ProgramData\\ZeroTier\\One\\zerotier-one_x64.exe'
$backup = "$target.previous"
$incoming = Join-Path $env:USERPROFILE 'zerotier-one_x64.exe.new'
$expectedHashFile = "$incoming.sha256"

$expectedHash = (Get-Content $expectedHashFile -Raw).Trim()
$actualHash = (Get-FileHash $incoming -Algorithm SHA256).Hash
if ($actualHash -ne $expectedHash) {
	throw "Uploaded binary hash mismatch: expected $expectedHash, got $actualHash"
}
if (-not (Test-Path $target)) {
	throw "Installed ZeroTier executable not found at $target"
}

$service = Get-Service $serviceName
if ($service.Status -ne 'Stopped') {
	Stop-Service $serviceName -Force
	$service.WaitForStatus('Stopped', '00:00:30')
}

$backupCreated = $false
try {
	Remove-Item $backup -Force -ErrorAction SilentlyContinue
	Move-Item $target $backup
	$backupCreated = $true
	Move-Item $incoming $target

	Start-Service $serviceName
	$service.WaitForStatus('Running', '00:00:30')
	Start-Sleep -Seconds 5
	if ((Get-Service $serviceName).Status -ne 'Running') {
		throw "$serviceName did not remain running"
	}

	$installedHash = (Get-FileHash $target -Algorithm SHA256).Hash
	if ($installedHash -ne $expectedHash) {
		throw "Installed binary hash mismatch: expected $expectedHash, got $installedHash"
	}
	Write-Output "$serviceName is running with SHA256 $installedHash"
} catch {
	$deploymentError = $_
	if ($backupCreated) {
		Stop-Service $serviceName -Force -ErrorAction SilentlyContinue
		(Get-Service $serviceName).WaitForStatus('Stopped', '00:00:30')
		Remove-Item $target -Force -ErrorAction SilentlyContinue
		Move-Item $backup $target -Force
	}
	if ((Get-Service $serviceName).Status -ne 'Running') {
		Start-Service $serviceName
		(Get-Service $serviceName).WaitForStatus('Running', '00:00:30')
	}
	throw $deploymentError
} finally {
	Remove-Item $incoming, $expectedHashFile -Force -ErrorAction SilentlyContinue
}
'''.stripIndent()
				withCredentials([sshUserPrivateKey(credentialsId: 'Popo', keyFileVariable: 'POPO_SSH_KEY', usernameVariable: 'POPO_SSH_USER')]) {
					exec '''
set -eu

POPO_IP="$(nslookup -type=A popo | awk '/^Name:/ { answer = 1; next } answer && $1 == "Address:" && $2 ~ /^[0-9]+[.]/ && $2 !~ /^169[.]254[.]/ { print $2; exit }')"
test -n "$POPO_IP"

ssh-keyscan -T 5 -t ed25519 "$POPO_IP" > .jenkins/popo_known_hosts
ACTUAL_HOST_KEY="$(ssh-keygen -lf .jenkins/popo_known_hosts -E sha256 | awk '{ print $2 }')"
test "$ACTUAL_HOST_KEY" = "$POPO_SSH_HOST_KEY_SHA256"

cp .jenkins/results/zerotier-one.exe zerotier-one_x64.exe.new
sha256sum zerotier-one_x64.exe.new | awk '{ print $1 }' > zerotier-one_x64.exe.new.sha256

scp -i "$POPO_SSH_KEY" -o "User=$POPO_SSH_USER" -o UserKnownHostsFile=.jenkins/popo_known_hosts -o StrictHostKeyChecking=yes \
	zerotier-one_x64.exe.new zerotier-one_x64.exe.new.sha256 "$POPO_IP:"
ssh -i "$POPO_SSH_KEY" -l "$POPO_SSH_USER" -o UserKnownHostsFile=.jenkins/popo_known_hosts -o StrictHostKeyChecking=yes \
	"$POPO_IP" powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File - < .jenkins/deploy.ps1
'''.stripIndent()
				}
			}
		}
	}
}
