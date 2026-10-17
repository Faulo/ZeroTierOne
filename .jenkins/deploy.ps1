$ErrorActionPreference = 'Stop'

$serviceName = 'ZeroTierOneService'
$target = 'C:\ProgramData\ZeroTier\One\zerotier-one_x64.exe'
$backup = "$target.previous"
$incoming = Join-Path $env:USERPROFILE 'zerotier-one.exe'

if (-not (Test-Path $incoming)) {
	throw "Uploaded ZeroTier executable not found at $incoming"
}
if (-not (Test-Path $target)) {
	throw "Installed ZeroTier executable not found at $target"
}

$expectedHash = (Get-FileHash $incoming -Algorithm SHA256).Hash
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
	Remove-Item $incoming -Force -ErrorAction SilentlyContinue
}
