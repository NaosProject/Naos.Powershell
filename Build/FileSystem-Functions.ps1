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