function Test-RunTestFunctions([string] $testFunctionPrefix)
{
	ls function: | ?{$_.Name.StartsWith($testFunctionPrefix, [System.StringComparison]::InvariantCultureIgnoreCase)}|%{
		Write-Output "> $($_.Name)"
		try {
			&$_
			Write-Output "  - SUCCESS"
		}
		catch
		{
			Write-Output "  ! FAILURE - $_"
			Write-Output "      IN FILE: $($_.InvocationInfo.ScriptName)"
			Write-Output "      AT LINE: $($_.InvocationInfo.ScriptLineNumber) OFFSET: $($_.InvocationInfo.OffsetInLine)"
		}
		Write-Output "< $($_.Name)"
	}
}