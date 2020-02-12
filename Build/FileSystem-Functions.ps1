function File-RemoveReadonlyFlag([System.Array] $files)
{
	if ($files -ne $null)
	{
		$files | %{
			if (Test-Path $_)
			{
				Set-ItemProperty $_ -name IsReadOnly -value $false
			}
		}
	}
}

function File-AddReadonlyFlag([System.Array] $files)
{
	if ($files -ne $null)
	{
		$files | %{
			if (Test-Path $_)
			{
				Set-ItemProperty $_ -name IsReadOnly -value $true
			}
		}
	}
}

function File-FindSolutionFileUnderPath([string] $path)
{
	if (-not (Test-Path $path))
	{
		throw "Path: $path does not exist, please verify"
	}

	$solutionFiles = ls $path -Filter *.sln
	
	if ($solutionFiles -eq $null)
	{
		throw "No solution files found at $path (not recursive), please verify"
	}
	
	# if more than one found thne type is array; else type is FileInfo
	if ($solutionFiles.GetType().Name -eq 'Object[]')
	{
		throw "Multiple solutions found in current directory, please specify $SolutionFile"
	}

	return $solutionFiles.FullName
}

function File-CreateTempDirectory([string] $prefix = 'Naos.FileTemp', [string] $rootPath = [System.IO.Path]::GetTempPath())
{
    if ([String]::IsNullOrWhitespace($prefix))
    {
        throw "Please specify a 'prefix' or leave black to use default of 'Naos.FileTemp'."
    }
    
    if ([String]::IsNullOrWhitespace($rootPath))
    {
        throw "Please specify a 'rootPath' or leave black to use default of 'Environment Temp Directory'."
    }

    [string] $tempDirectoryName = $prefix + '_' + [System.DateTime]::UtcNow.ToString('yyyyMMddTHHmmssZ')
    $tempDirectoryPath = Join-Path $rootPath $tempDirectoryName
    if (Test-Path $tempDirectoryPath)
    {
        throw "Path ($tempDirectoryPath) exists; this was not expected."
    }

    New-Item -ItemType Directory -Path $tempDirectoryPath | Out-Null
    return $tempDirectoryPath
}

function File-TryDeleteTempDirectories([string] $prefix = 'Naos.FileTemp', [string] $rootPath = [System.IO.Path]::GetTempPath())
{
    if ([String]::IsNullOrWhitespace($prefix))
    {
        throw "Please specify a 'prefix' or leave black to use default of 'Naos.FileTemp'."
    }
    
    if ([String]::IsNullOrWhitespace($rootPath))
    {
        throw "Please specify a 'rootPath' or leave black to use default of 'Environment Temp Directory'."
    }
    
    $priorTempDirectories = [System.IO.Directory]::GetDirectories($rootPath, $prefix + '*')
    $priorTempDirectories | %{
        $tempDirectory = $_
        try
        {
            Remove-Item $tempDirectory -Recurse -Force -ErrorAction SilentlyContinue
            Write-Output "Removed old temp directory ($tempDirectory)"
        }
        catch
        {
            Write-Output "Failed to remove old temp directory ($tempDirectory)"
        }
    }
}

function File-ThrowIfPathMissing([string] $path, [string] $because)
{
    if (-not (Test-Path $path))
    {
        $message = "Test-Path - expected path not found ($path)"
        if ([String]::IsNullOrWhitespace($because))
        {
            $message = "$message."
        }
        else
        {
            $message = "$message; $because"
        }
        
        throw $message
    }
}

function File-FindReplaceInFileName([string] $directoryPath, [boolean] $recurse = $true, [string] $find, [string] $replace)
{    
    File-ThrowIfPathMissing -path $directoryPath
    $directoryItem = Get-Item $directoryPath
    if (-not $directoryItem.PSIsContainer)
    {
        throw "Must specify a path to a directory; specified path is not a directory ($directoryPath)."
    }

    $filePathsRaw = $null
    if ($recurse -eq $true)
    {
        $filePathsRaw = ls $directoryPath -Recurse
    }
    else
    {
        $filePathsRaw = ls $directoryPath
    }
    
    $filePaths = $filePathsRaw | ?{-not $_.PSIsContainer} | %{$_.FullName}
    $filePaths | %{
        $filePath = $_
        $fileDirectoryPath = Split-Path $filePath
        $fileName = Split-Path $filePath -Leaf
        $newFileName = $fileName.Replace($find, $replace)
        if ($fileName -ne $newFileName)
        {
            $newFilePath = Join-Path $fileDirectoryPath $newFileName
            Move-Item $filePath $newFilePath
        }
    }
}