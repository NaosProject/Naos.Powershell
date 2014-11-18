# this will install Naos-GitBrachingTools.ps1 into your powershell profile

# constants
$ScriptsPath = "C:\Scripts"
$GitBranchingScriptPath = Join-Path $ScriptsPath 'Naos-GitBrachingTools.ps1'

# create c:\Scripts
New-Item -ItemType Directory $ScriptsPath -Force | Out-Null

# install GitBranchingTools script.  Always fetch latest file, but check if file is already dot-sourced before adding to profile
Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/NaosFramework/Powershell/master/GIT/Naos-GitBrachingTools.ps1' -OutFile $GitBranchingScriptPath
Unblock-File -Path $GitBranchingScriptPath
if ( ( Get-Content $PROFILE | Where-Object { $_.Contains( $GitBranchingScriptPath ) } ) -eq $null )
{
    Add-Content $PROFILE "`n# Load git branching tools"
    Add-Content $PROFILE ". $($GitBranchingScriptPath)"
}

