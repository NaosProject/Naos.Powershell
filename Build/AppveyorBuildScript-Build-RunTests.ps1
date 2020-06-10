$path = Resolve-Path .
 $projectFileExtension = 'csproj'
 $hasTestFailure = $false
 $csProjFilePaths = ls $path -filter "*.$projectFileExtension" -recurse | %{$_.FullName} | ?{$_.ToLower().EndsWith(".test.$projectFileExtension") -or $_.ToLower().EndsWith(".tests.$projectFileExtension")}
 
 Write-Output ''
 Write-Output "================ STARTING TESTING ================"
 $csProjFilePaths | %{
     Write-Output "Discovered test project: $_"
 }
​
 $csProjFilePaths | %{
    $csProjFilePath = $_
    $csProjFileName = Split-Path $csProjFilePath -Leaf
    $csProjDirectoryPath = Split-Path $csProjFilePath
    $csProjAssemblyPathWithoutExtension = Join-Path (Join-Path $csProjDirectoryPath 'bin\Debug') $csProjFileName.Replace(".$projectFileExtension", '')
    $exePath = "$csProjAssemblyPathWithoutExtension.exe"
    $DllPath = "$csProjAssemblyPathWithoutExtension.dll"
​
    Write-Output ''
    Write-Output "================ START TEST $csProjFileName ================"
​
    if (Test-Path $exePath)
    {
        &(Join-Path $env:xunit20 'xunit.console.x86') $exePath -appveyor
        if(($lastExitCode -ne 0) -and (-not $hasTestFailure))
        {
            $hasTestFailure = $true
        }
    }
    elseif (Test-Path $dllPath)
    {
        &(Join-Path $env:xunit20 'xunit.console.x86') $dllPath -appveyor
        if(($lastExitCode -ne 0) -and (-not $hasTestFailure))
        {
            $hasTestFailure = $true
        }
    }
    else
    {
        throw "Expected to either find assembly: $exePath or $dllPath.  Neither were found, please verify that the output assembly is named the same as the project."
    }
​
    Write-Output "================ END TEST $csProjFileName ================"
    Write-Output ''
 }
​
 if ($hasTestFailure)
 {
     throw "A unit test has failed.  Test runner exited with non-0 exit code.  See output above for details."
 }
 else
 {
     Write-Output ''
     Write-Output "================ COMPLETED TESTING ================"
 }
