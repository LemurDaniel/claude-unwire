# Mock router of the Unwire testbed: PowerShell 7 with the HttpListener of .NET, no modules.
FROM mcr.microsoft.com/powershell:7.4-ubuntu-22.04

WORKDIR /mock-router
COPY Start-MockRouter.ps1 ./
COPY data/ ./data/
COPY www/ ./www/

# One port per login method, see data/mock-router.variants.json
EXPOSE 3010-3016

CMD ["pwsh", "-NoProfile", "-File", "/mock-router/Start-MockRouter.ps1"]
