param([string] $projectName)

    # Get path of current script to allow help printing and dotSourcing sibling scripts.
    $currentScriptPath = ((Get-Variable MyInvocation -Scope 0).Value).MyCommand.Path

    # dot source some standard reusable methods.
    $buildScriptsPath = Join-Path (Split-Path $currentScriptPath) "../Build"
	. (Join-Path $buildScriptsPath VisualStudio-Functions.ps1)
 
    # do the work.
    VisualStudio-CheckNuGetPackageDependencies -projectName $projectName