# escape=`

FROM faulo/unreal:latest

SHELL ["C:/Windows/System32/WindowsPowerShell/v1.0/powershell", "-ExecutionPolicy", "Bypass", "-NonInteractive", "-NoProfile", "-Command", "$ErrorActionPreference = 'Stop'; $ProgressPreference = 'SilentlyContinue';"]

USER ContainerAdministrator
WORKDIR C:/zerotier-build

COPY install-build-tools.ps1 C:/zerotier-build/install-build-tools.ps1
RUN & C:/zerotier-build/install-build-tools.ps1

ENV CARGO_HOME="C:\cargo" `
    RUSTUP_HOME="C:\rustup" `
    VCPKG_ROOT="C:\vcpkg" `
    VCPKG_FORCE_SYSTEM_BINARIES="1" `
    VCPKG_KEEP_ENV_VARS="PATH"

RUN where.exe cl; `
    if ($LASTEXITCODE -ne 0) { throw 'MSVC compiler is not on PATH' }; `
    cmake --version; `
    ninja --version; `
    cargo --version; `
    rustc --version; `
    vcpkg version

WORKDIR C:/workspace
