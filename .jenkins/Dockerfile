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
    PATH="C:\cmake\bin;C:\cargo\bin;C:\vcpkg;${PATH}"

RUN cmake --version; `
    cargo --version; `
    rustc --version; `
    vcpkg version

WORKDIR C:/workspace
