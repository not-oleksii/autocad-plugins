# Prepares and publishes BPTOOLS releases on GitHub with ..\commonelease.ps1 (see "Releasing" in
# DEVELOPING.md):
#   release.ps1 -Prepare 1.0.0   on a branch: set the version and date the changelog
#   release.ps1 [-DryRun]         on main, after that branch is merged: build, test, tag, publish
param(
    [string]$Prepare,
    [switch]$DryRun
)
& (Join-Path $PSScriptRoot '..\commonelease.ps1') -Plugin $PSScriptRoot -Prepare $Prepare -DryRun:$DryRun
exit $LASTEXITCODE
