$helpConstants = @{
   Usage = @{
        AllSwitchName = 'All';
        IncludedInAllPrefix = 'INCLUDED WITH ALL SWITCH: ';
        RequiredPrefix = 'REQUIRED: ';
    }
}

function Help-GetSpacesForUsage(
    [Parameter(Mandatory=$true)]
    [int] $Length)
{
    <#
        .SYNOPSIS 
        Constructs a string of spaces.
        .PARAMETER Length
        The number of spaces to include in the string.
        .INPUTS
        No pipeline inputs accepted.
        .OUTPUTS
        A string of the length specified with all spaces or an empty string if the specified length is <= 0
    #>
    if ($Length -lt 0) { return "" }
    $spaces = New-Object String(" ", $Length)
    return $spaces
}

function Help-WriteScriptUsageLine(
                        [Parameter(Mandatory=$true)]
                        [int] $BlockWidth,
                        [Parameter(Mandatory=$true)]
                        [int] $IndentLevel ,
                        [Parameter(Mandatory=$true)]
                        [int] $IndentWidth ,
                        [Parameter(Mandatory=$true)]
                        [bool] $IncreaseIndentLevelUponLineBreak ,
                        [Parameter(Mandatory=$true)]
                        [AllowEmptyString()]
                        [string] $TextToWrite ,
                        [int] $IndentWidthUponLineBreak = 0 ,
                        [bool] $LineBreakApplied = $false )
{
    <#
        .SYNOPSIS 
        Write a single string of text to a script usage block.
        .PARAMETER BlockWidth
        The width of the script usage block.  This function will break-up text and put it on multiple lines to respect the width of the usage block.
        .PARAMETER IndentLevel
        The level of indentation to apply to the text being written.
        0 or less means no indentiation; the text will start right after the dash + space (a usage-block's standard beginning-of-line delimiter).
        X means X-levels of identation: dash + space + ( X * $IndentWidth )
        .PARAMETER IndentWidth
        The number of spaces to insert for each level of Indentation.
        0 or less means no spaces and thus no indentation, regardless of $IndentLevel
        .PARAMETER IncreaseIndentLevelUponLineBreak
        Determines if the indent level should be increased by 1 if the text-to-write has to be broken up into multiple lines.  If $true, then all lines after the first will be indented at $IndentLevel + 1
        .PARAMETER TextToWrite
        The usage text to write.  Should represent one element of usage in an entire usage-block (i.e. the definition of a single parameter, one example of how to all the script, etc.)
        .PARAMETER IndentWidthUponLineBreak
        Specifies the indent to apply on all lines after the first, if the text-to-write has to be broken up into multiple lines.  This fixed-width identation will be applied in conjunction to $IdentLevel.
        .PARAMETER LineBreakApplied
        FOR USE BY THE FUNCTION ITSELF.  Determines if a line break was applied to the text being written.
        .INPUTS
        No pipeline inputs accepted.
        .OUTPUTS
        None.  Writes $TextToWrite within a script usage block to Host.
    #>
    
    # start with a dash + space
    $line = "- "

    # indent to proper level
    $line = $line + (Help-GetSpacesForUsage ($IndentWidth * $IndentLevel))

    # if a line-break was applied then also ident by $IndentWidthUponLineBreak
    if ( $LineBreakApplied -eq $true )
    {
        $line = $line + (Help-GetSpacesForUsage $IndentWidthUponLineBreak)
    }

    # write the identation to Host
    Write-Host -NoNewline $line

    # now split the text to write into words.  iterate through each word
    # and write it to Host, then determine whether the next word can be written 
    # or otherwise introduce a line break
    $wordsToWrite = $TextToWrite.Split(" ")
    for ($wordIndex = 0; $wordIndex -lt $wordsToWrite.Length; $wordIndex++)
    {
        # write the current word + space
        Write-Host -NoNewline ($wordsToWrite[ $wordIndex ] + " ")
        $line = $line + $wordsToWrite[$wordIndex] + " "

        # is there a next word?
        if (($wordIndex + 1) -lt $wordsToWrite.Length)
        {

            # if we were to write the next word + space + ending dash, would we exceed the usage block width?
            if (($line.Length + $wordsToWrite[$wordIndex + 1].Length + 1 + 1) -gt $BlockWidth)
            {
                # write the remainder of the line, which is enough spaces followed by a dash to gets us to $BlockWidth characters.
                $endOfLine = (Help-GetSpacesForUsage ($BlockWidth - $line.Length - 1 )) + "-"
                Write-Host $endOfLine

                # construct the unwritten text
                $TextToWrite = [string]::Join(" ", $wordsToWrite, $wordIndex + 1, $wordsToWrite.Length - $wordIndex - 1)

                # determine if the indent level should be increased for the next line and all subsequent lines
                if ((-Not $LineBreakApplied) -And ($IncreaseIndentLevelUponLineBreak)) { $IndentLevel++ }

                # write the next line of text
                Help-WriteScriptUsageLine -BlockWidth $BlockWidth -IndentLevel $IndentLevel -IndentWidth $IndentWidth -IncreaseIndentLevelUponLineBreak $IncreaseIndentLevelUponLineBreak -TextToWrite $TextToWrite -IndentWidthUponLineBreak $IndentWidthUponLineBreak -LineBreakApplied $true
                return
            }
        }
    }

    # write the remainder of the line, which is enough spaces followed by a dash to gets us to $BlockWidth characters.
    $endOfLine = (Help-GetSpacesForUsage ($BlockWidth - $line.Length - 1 )) + "-"
    Write-Host $endOfLine
    return
}

function Help-WriteScriptUsageBlock( 
                        [Parameter(Mandatory=$true)]
                        [string] $ScriptPath )
{
    <#
        .SYNOPSIS
        Write a script usage block.
        .PARAMETER ScriptPath
        The full path to the script.
        .INPUTS
        No pipeline inputs accepted.
        .OUTPUTS
        None.  Writes a script usage block to Host.
    #>
    
    # some constants
    [int] $CommentBlockWidth = 115
    [int] $IndentWidth = 3

    # some reusable lambdas
    [scriptblock] $writeBlankLine = {
        Help-WriteScriptUsageLine -BlockWidth $CommentBlockWidth -IndentLevel 0 -IndentWidth 0 -IncreaseIndentLevelUponLineBreak $false -TextToWrite ""
    }

    # write top line with file name
    $filePath = Split-Path $ScriptPath -Leaf
    $charsToFillWithDashes = $CommentBlockWidth - $filePath.Length - 2
    $dashesOnLeft = [Convert]::ToInt32($charsToFillWithDashes/2)
    $dashesOnRight = $charsToFillWithDashes - $dashesOnLeft
    Write-Host "$( New-Object String("-", $dashesOnLeft)) $filePath $( New-Object String( "-" , $dashesOnRight))"
    & $writeBlankLine

    # get the powershell help to use as source data
    $scriptHelp = Get-Help $ScriptPath -Detailed
    
    # write the synopsis
    $synopsis = $scriptHelp.Synopsis
    Help-WriteScriptUsageLine -BlockWidth $CommentBlockWidth -IndentLevel 1 -IndentWidth $IndentWidth -IncreaseIndentLevelUponLineBreak $true -TextToWrite $synopsis
    & $writeBlankLine

    # write the examples
    $scriptHelp.Examples.Example.Code | %{
        Help-WriteScriptUsageLine -BlockWidth $CommentBlockWidth -IndentLevel 2 -IndentWidth $IndentWidth -IncreaseIndentLevelUponLineBreak $true -TextToWrite $_
    }
    & $writeBlankLine

    # write parameters
    $params = $scriptHelp.Parameters.parameter | ?{ $_.parameterValue -ne "SwitchParameter" }
    if ($params.Count -gt 0)
    {
        Help-WriteScriptUsageLine -BlockWidth $CommentBlockWidth -IndentLevel 1 -IndentWidth $IndentWidth -IncreaseIndentLevelUponLineBreak $true -TextToWrite "Parameter descriptions:"
        & $writeBlankLine

        $maxParamNameSize = ($params | %{$_.Name.Length} | Sort-Object -Descending)[0]
        $maxParamTypeSize = ($params | %{$_.ParameterValue.Length} | Sort-Object -Descending)[0]

        $params | %{
            $parameter = $_
            $typeAsText = "[" + $parameter.parameterValue + "]"
            $requiredText = "Optional"; if (($parameter.required -eq $true) -or ($parameter.description.Text.StartsWith($helpConstants.Usage.RequiredPrefix))) { $requiredText = "Required" }
            $textToWrite = "-" + $parameter.Name + (Help-GetSpacesForUsage ($maxParamNameSize - $parameter.Name.Length)) + "  " + $typeAsText + (Help-GetSpacesForUsage ($maxParamTypeSize - $typeAsText.Length)) + "  " + $requiredText + " - " 
            $indentToAlignDescription = $textToWrite.Length
            $textToWrite = $textToWrite + $parameter.description.Text.Replace($helpConstants.Usage.RequiredPrefix, '')
            Help-WriteScriptUsageLine -BlockWidth $CommentBlockWidth -IndentLevel 2 -IndentWidth $IndentWidth -IncreaseIndentLevelUponLineBreak $false -TextToWrite $textToWrite -IndentWidthUponLineBreak $indentToAlignDescription
            & $writeBlankLine
        }
    }

    # write switches
    $switches = $scriptHelp.Parameters.parameter | ?{ $_.parameterValue -eq "SwitchParameter" }
    if ($switches.Count -gt 0)
    {
        Help-WriteScriptUsageLine -BlockWidth $CommentBlockWidth -IndentLevel 1 -IndentWidth $IndentWidth -IncreaseIndentLevelUponLineBreak $true -TextToWrite "Switch descriptions: Presence will be true, absense will be false:"
        & $writeBlankLine

        $switchesIndentLevel = 2
        $switchesIndentLevelInAll = 3
        $allSwitch = $switches | ?{ $_.name -eq $helpConstants.Usage.AllSwitchName }
        $inAllSwitches = $switches | ?{ $_.name -ne $helpConstants.Usage.AllSwitchName } | ?{ $_.description.text.StartsWith($helpConstants.Usage.IncludedInAllPrefix) }
		if ($inAllSwitches -eq $null) #might not have the concept of an ALL switches
		{
			$inAllSwitches = @{}
		}
		else
		{
			if ($inAllSwitches.GetType().BaseType.ToString() -ne 'System.Array') # only one element will not be a collection and must be converted into one for checks and piping to work...
			{
				$inAllSwitches = ,$inAllSwitches
			}
		}
        
        $notInAllSwitches = $switches | ?{ $_.name -ne $helpConstants.Usage.AllSwitchName } | ?{ -not $_.description.text.StartsWith($helpConstants.Usage.IncludedInAllPrefix) }
        if ($notInAllSwitches.GetType().BaseType.ToString() -ne 'System.Array') # only one element will not be a collection and must be converted into one for checks and piping to work...
        {
            $notInAllSwitches = ,$notInAllSwitches
        }
        

        if ($notInAllSwitches.Count -gt 0)
        {
            $maxSwitchSizeNotInAll = ($notInAllSwitches | %{$_.Name.Length} | Sort-Object -Descending)[0]
            $notInAllSwitches | %{
                $switch = $_
                $textToWrite = "-" + $switch.Name + (Help-GetSpacesForUsage ($maxSwitchSizeNotInAll - $switch.Name.Length)) + " : "
                $indentToAlignDescription = $textToWrite.Length
                $textToWrite = $textToWrite + $switch.description.Text
                Help-WriteScriptUsageLine -BlockWidth $CommentBlockWidth -IndentLevel $switchesIndentLevel -IndentWidth $IndentWidth -IncreaseIndentLevelUponLineBreak $false -TextToWrite $textToWrite -IndentWidthUponLineBreak $indentToAlignDescription
            }

            & $writeBlankLine
        }

        if ( $allSwitch -ne $null )
        {
            $allSwitchDescription = "-All - Will assume all below to be true / present / set"
            Help-WriteScriptUsageLine -BlockWidth $CommentBlockWidth -IndentLevel $switchesIndentLevel -IndentWidth $IndentWidth -IncreaseIndentLevelUponLineBreak $false -TextToWrite $allSwitchDescription

            & $writeBlankLine
        }

        if ($inAllSwitches.Count -gt 0)
        {
            $maxSwitchSizeInAll = ($inAllSwitches | %{$_.Name.Length} | Sort-Object -Descending)[0]
            $inAllSwitches | %{
                $switch = $_
                $textToWrite = "-" + $switch.Name + (Help-GetSpacesForUsage ($maxSwitchSizeInAll - $switch.Name.Length)) + " : "
                $indentToAlignDescription = $textToWrite.Length
                $textToWrite = $textToWrite + $switch.description.Text.Replace($helpConstants.Usage.IncludedInAllPrefix, '')
                Help-WriteScriptUsageLine -BlockWidth $CommentBlockWidth -IndentLevel $switchesIndentLevelInAll -IndentWidth $IndentWidth -IncreaseIndentLevelUponLineBreak $false -TextToWrite $textToWrite -IndentWidthUponLineBreak $indentToAlignDescription
            }

            & $writeBlankLine
        }
    }

    $moreHelpMessage1 = "For more help see native Powershell help:"
    $moreHelpMessage2 = "> Get-Help $ScriptPath -Detailed"
    Help-WriteScriptUsageLine -BlockWidth $CommentBlockWidth -IndentLevel 1 -IndentWidth $IndentWidth -IncreaseIndentLevelUponLineBreak $false -TextToWrite $moreHelpMessage1 -IndentWidthUponLineBreak $indentToAlignDescription
    Help-WriteScriptUsageLine -BlockWidth $CommentBlockWidth -IndentLevel 2 -IndentWidth $IndentWidth -IncreaseIndentLevelUponLineBreak $false -TextToWrite $moreHelpMessage2 -IndentWidthUponLineBreak $indentToAlignDescription
    
    # end the usage block
    & $writeBlankLine    
    Write-Host "$( New-Object String("-" , $CommentBlockWidth) )"

}
