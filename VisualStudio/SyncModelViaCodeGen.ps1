#SyncModelViaCodeGen.ps1

param(
	[string] $projectName,
    [string] $testProjectName = $null,
	[string] $sourceRoot = 'D:\SourceCode\')
    
    if ($projectName.StartsWith('.\'))
    {
        # compensate for if auto complete was used which will do the directory in context of the solution folder (strictly a convenience).
        $projectName = $projectName.SubString(2, $projectName.Length - 2)
    }
    
    if ($testProjectName.StartsWith('.\'))
    {
        # compensate for if auto complete was used which will do the directory in context of the solution folder (strictly a convenience).
        $testProjectName = $testProjectName.SubString(2, $testProjectName.Length - 2)
    }
    
    if ([string]::IsNullOrWhitespace($projectName))
    {
        throw 'Specify Project Name to operate on.'
    }
    
    if ([string]::IsNullOrWhitespace($testProjectName))
    {
        $testProjectName = $projectName + ".Test"
    }
    
    function Reflection-LoadAssembly([string] $assemblyFilePath)
    {
        $assemblyBytes = [System.IO.File]::ReadAllBytes($assemblyFilePath)
        [System.Reflection.Assembly]::Load($assemblyBytes)
    }
    
    # Get path of current script to allow help printing and dotSourcing sibling scripts.
    $currentScriptPath = ((Get-Variable MyInvocation -Scope 0).Value).MyCommand.Path

    # dot source some standard reusable methods.
    $buildScriptsPath = Join-Path (Split-Path $currentScriptPath) "../Build"
	. (Join-Path $buildScriptsPath MsBuild-Functions.ps1)
	. (Join-Path $buildScriptsPath NuGet-Functions.ps1)
	. (Join-Path $buildScriptsPath VisualStudio-Functions.ps1)

    $solution = $DTE.Solution
    $solutionDirectory = Split-Path $solution.FileName
    $projectDirectory = Join-Path $solutionDirectory $projectName
    $testProjectDirectory = Join-Path $solutionDirectory $testProjectName
    
    if (-not (Test-Path $projectDirectory))
    {
        throw "Expected $projectDirectory to exist."
    }
    
    if (-not (Test-Path $testProjectDirectory))
    {
        throw "Expected $testProjectDirectory to exist."
    }
    
    $projectFilePath = (ls $projectDirectory -Filter '*.csproj').FullName
    $testProjectFilePath = (ls $testProjectDirectory -Filter '*.csproj').FullName

    D:\SourceCode\OBeautifulCode\OBeautifulCode.CodeGen\OBeautifulCode.CodeGen.Generator.Console\bin\Debug\OBeautifulCode.CodeGen.Generator.Console.exe model /projectDirectory=$projectDirectory /testProjectDirectory=$testProjectDirectory

    $projectFilesFromCsproj = VisualStudio-GetFilePathsFromProject -projectFilePath $projectFilePath
    $testProjectFilesFromCsproj = VisualStudio-GetFilePathsFromProject -projectFilePath $testProjectFilePath
    
    $project = VisualStudio-GetProjectFromSolution -projectFilePath $projectFilePath
    $testProject = VisualStudio-GetProjectFromSolution -projectFilePath $testProjectFilePath
    
    $projectSouceFiles = ls $projectDirectory -filter '*.cs' -recurse | %{ $_.FullName } | ?{-not $_.Contains('\obj\')}
    $testProjectSourceFiles = ls $testProjectDirectory -filter '*.cs' -recurse | %{ $_.FullName } | ?{-not $_.Contains('\obj\')}
    
    $projectSouceFiles | ?{ -not $projectFilesFromCsproj.Contains($_) } | %{ $project.ProjectItems.AddFromFile($_) }
    $testProjectSourceFiles | ?{ -not $testProjectFilesFromCsproj.Contains($_) } | %{ $testProject.ProjectItems.AddFromFile($_) }
    
    # $tempPathBase = Resolve-Path (Join-Path $solutionDirectory '../../')
    # $tempPath = Join-Path $tempPathBase 'TempNuGetCachingForPowershellScripts'
    
    # &$NuGetExeFilePath install 'OBeautifulCode.CodeGen.ModelObject' -OutputDirectory $tempPath
    # $codeGenAssemblyDirs = ls $tempPath -Filter 'OBeautifulCode.CodeGen.ModelObject*' | %{ $_.FullName } | Sort-Object -Descending
    # $codeGenAssemblyFilePath = Join-Path $codeGenAssemblyDirs[0] 'lib/net462/OBeautifulCode.CodeGen.ModelObject.dll'
    # Write-Output "Loading assembly $codeGenAssemblyFilePath"
    # Reflection-LoadAssembly -assemblyFilePath $codeGenAssemblyFilePath

    # $projectAssemblyFileName = MsBuild-GetOutputFileName -projectFilePath $projectFilePath
    # $projectAssemblyFilePath = Join-Path $projectDirectory "bin/debug/$projectAssemblyFileName"

    # $projectAssemblyOutputDirectory = Join-Path $projectDirectory "bin/debug"

    
    # if (-not (Test-Path $projectAssemblyOutputDirectory))
    # {
        # throw "Cannot file file: $projectAssemblyOutputDirectory, make sure you have built the project."
    # }
    
    # Write-Output "Loading assemblies in $projectAssemblyOutputDirectory"
    # ls $projectAssemblyOutputDirectory | %{$_.FullName} | %{
        # $fileCandidate = $_
        # if ($fileCandidate.EndsWith('.dll') -or $fileCandidate.EndsWith('.exe'))
        # {
            # Reflection-LoadAssembly -assemblyFilePath $fileCandidate
        # }
    # }
    
    
    # $kind = [OBeautifulCode.CodeGen.ModelObject.GenerateFor]::ModelImplementationPartialClass
    # $loadedAssemblies = [AppDomain]::CurrentDomain.GetAssemblies()
    # $assembliesToConsider = $loadedAssemblies | ?{$_.FullName.StartsWith($projectName)}

    # $assemblyInQuestion = $assembliesToConsider[$assembliesToConsider.Length - 1]
    
    # if ($assemblyInQuestion -ne $null)
    # {
        # $typesToConsider = $assemblyInQuestion.GetTypes()
        # $typesToConsider | %{
            # $type = $_
            # Write-Output "Considering $type"
            # $interfaces = $type.GetInterfaces()
            # if ($interfaces | ?{$_ -ne $null} | ?{$_.FullName -ne $null} | ?{$_.FullName.StartsWith('OBeautifulCode.Type.IModelViaCodeGen')})
            # {
                # Write-Output "Found model to update: $type"
                # $partialClassOutput = [OBeautifulCode.CodeGen.ModelObject.CodeGenerator]::GenerateForModel($type, $kind)
                # Write-Output $partialClassOutput
                # throw "maybe"
            # }
        # }
    # }