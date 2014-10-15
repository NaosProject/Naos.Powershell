function Validate-RepoState()
{
    <#
        .SYNOPSIS 
        Validates that a git repository is in the right state to apply the branching model.
        .INPUTS
        No pipeline inputs accepted.
        .OUTPUTS
        Returns $null if the repo state is valid.  Otherwise, throws.
    #>

    # prompt to close out files
    Write-Host "Does anything hold a lock on any file in the current branch?  If so, close it out." -ForegroundColor "green"
    do { $result = Read-Host -Prompt "[D]one" }
    while ( $result.ToLower() -ne "d" )

    # check posh-git
    # note: probably a better way to do this than looking for Get-GitStatus
    if (-Not ( Get-Command Get-GitStatus -errorAction SilentlyContinue) )
    {
        throw "Please install PoshGit.  Suggest using Chocolatey to install."
    }

    # validate that this script is running from a branch, not master
    $branch = (Get-GitStatus).Branch
    if ( $branch -eq "master" )
    {
        throw "You cannot run this script from master, it must be run from a branch."
    }

    # validate that there are no uncommitted changes on the branch
    # https://stackoverflow.com/questions/3878624/how-do-i-programmatically-determine-if-there-are-uncommited-changes
    git diff --quiet HEAD
    if ( $LASTEXITCODE -ne 0 )
    {
        throw "There are changes on this branch that have not been committed (either staged or unstaged)."
    }

    # check mergetool exists
    $mergeTool = git config --get merge.tool
    if ( [string]::IsNullOrWhiteSpace( $mergeTool ) )
    {
        throw "There is no merge tool setup.  If using BeyondCompare, do this: http://www.scootersoftware.com/support.php?zz=kb_vcs#gitwindows"
    }

    return $null
}

function BranchUp()
{
    <#
        .SYNOPSIS 
        Implements a simple git branching model described here: https://gist.github.com/jbenet/ee6c9ac48068889b0912
        Rebases master onto the current branch, iteratively calling the mergetool and continuing when there are merge conflicts.
        .INPUTS
        No pipeline inputs accepted.
        .OUTPUTS
        Returns $null when complete
    #>

    # perform validation
    Write-Host "Performing some validation..."
    Validate-RepoState

    # ensure everything is up-to-date in master
    $branch = (Get-GitStatus).Branch
    Write-Host "Update master with what's on GitHub..."
    git checkout master
    do { git pull origin master }
    while ( $LASTEXITCODE -ne 0 )
    Invoke-Expression "git checkout '$($branch)'"

    # rebase to ensure an easy merge from branch into master    
    # https://stackoverflow.com/questions/3921409/how-to-know-if-there-is-a-git-rebase-in-progress
    # https://stackoverflow.com/questions/10032265/how-do-i-make-git-automatically-open-the-mergetool-if-there-is-a-merge-conflict
    Write-Host "Rebase master onto $($branch)..."
    git rebase origin/master
    while ( (Get-GitStatus).Branch -like "*REBASE" )
    {
        git mergetool
        git clean -d -f
        git rebase --continue
    }

    Write-Host "master has been fully rebased onto $($branch)."
    return $null
}


function GitUp()
{
    <#
        .SYNOPSIS 
        Implements a simple git branching model described here: https://gist.github.com/jbenet/ee6c9ac48068889b0912.
        No support for shared branches - assumes branches are local only.
        Calls BranchUp and then merges branch into master, pushes master to GitHub, and deletes the branch.
        .INPUTS
        No pipeline inputs accepted.
        .OUTPUTS
        Returns $null when complete
    #>

    # setup branch for a clean merge into master
    BranchUp
    $branch = (Get-GitStatus).Branch

    # merge when done developing.
    # --no-ff preserves feature history and easy full-feature reverts
    # merge commits should not include changes; rebasing reconciles issues
    Write-Host "Merging with master..."
    git checkout master
    do { git pull origin master }
    while ( $LASTEXITCODE -ne 0 )
    Invoke-Expression "git merge --no-ff '$($branch)'"

    # push to github
    Write-Host "Push master to GitHub..."  
    do { git push origin master }
    while ( $LASTEXITCODE -ne 0 )
    
    # delete the branch
    Write-Host "Delete $($Branch)..."
    Invoke-Expression "git branch -d '$($branch)'"    

    return $null
}