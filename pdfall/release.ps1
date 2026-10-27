# Prepares and publishes PDFALL releases on GitHub with ..\common\release.ps1 (see "Releasing" in
# DEVELOPING.md):
#   release.ps1 -Prepare 1.12.0   on a branch: set the version and date the changelog
#   release.ps1 [-DryRun]          on main, after that branch is merged: build, test, tag, publish
param(
    [string]$Prepare,
    [switch]$DryRun
)
& (Join-Path $PSScriptRoot '..\common\release.ps1') -Plugin $PSScriptRoot -Prepare $Prepare -DryRun:$DryRun
exit $LASTEXITCODE
