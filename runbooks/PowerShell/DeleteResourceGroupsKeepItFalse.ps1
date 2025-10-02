<#
.SYNOPSIS
    Deletes Azure Resource Groups that do not have the 'keepIt' tag set to 'true'.

.DESCRIPTION
    This runbook connects to Azure using a Managed Identity and deletes all resource groups
    that either don't have a 'keepIt' tag or have it set to a value other than 'true'.
    Resource groups with 'keepIt=true' are preserved.
    
    IMPORTANT: This runbook is DISABLED by default. You must set $EnableDeletion = $true
    to activate it.

.PARAMETER EnableDeletion
    REQUIRED: Must be set to $true to allow the runbook to delete resource groups.
    This is a safety mechanism to prevent accidental deletions.

.PARAMETER MonitorJobs
    If specified, waits for all deletion jobs to complete before finishing.
    Default is $false (trigger deletions and exit).

.PARAMETER JobTimeoutSeconds
    The timeout in seconds for waiting for each resource group deletion job to complete.
    Default is 300 seconds (5 minutes). Only applies when MonitorJobs is $true.

.PARAMETER ExcludeResourceGroups
    Array of resource group names to exclude from deletion, regardless of tags.

.NOTES
    Requires:
    - Azure Automation Account with System-assigned Managed Identity
    - Managed Identity must have Contributor or Owner role on the subscription
    - Az.Accounts and Az.Resources modules

.EXAMPLE
    # First run - will show warning and exit
    .\DeleteResourceGroupsKeepItFalse.ps1
    
.EXAMPLE
    # Production run (fire and forget)
    .\DeleteResourceGroupsKeepItFalse.ps1 -EnableDeletion $true

.EXAMPLE
    # Active run with monitoring
    .\DeleteResourceGroupsKeepItFalse.ps1 -EnableDeletion $true -MonitorJobs $true
#>

[CmdletBinding()]
param(
	[Parameter(Mandatory = $false, HelpMessage = "SAFETY: Must be set to `$true to enable deletions")]
	[bool]$EnableDeletion = $false,
    
	[Parameter(Mandatory = $false)]
	[bool]$MonitorJobs = $false,
    
	[Parameter(Mandatory = $false)]
	[int]$JobTimeoutSeconds = 300,
    
	[Parameter(Mandatory = $false)]
	[string[]]$ExcludeResourceGroups = @()
)

# Safety check - runbook is disabled by default
if (-not $EnableDeletion) {
	Write-Output "=========================================="
	Write-Output "⚠️  RUNBOOK IS DISABLED ⚠️"
	Write-Output "=========================================="
	Write-Output ""
	Write-Output "This runbook will DELETE Azure Resource Groups that don't have 'keepIt=true' tag."
	Write-Output ""
	Write-Output "To activate this runbook, you must:"
	Write-Output "1. Review the code and understand what it does"
	Write-Output "2. Ensure all critical resource groups have the 'keepIt=true' tag"
	Write-Output "3. Set the parameter: -EnableDeletion `$true"
	Write-Output ""
	Write-Output "Example: Start-AzAutomationRunbook -Name 'YourRunbookName' -Parameters @{ EnableDeletion = `$true }"
	Write-Output ""
	Write-Output "=========================================="
	Write-Error "Runbook execution blocked. Set -EnableDeletion `$true to proceed."
	exit 1
}

# Function to write structured output
function Write-Log {
	param(
		[string]$Message,
		[ValidateSet('Info', 'Warning', 'Error')]
		[string]$Level = 'Info'
	)
    
	$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
	$output = "[$timestamp] [$Level] $Message"
    
	switch ($Level) {
		'Error' { Write-Error $output }
		'Warning' { Write-Warning $output }
		default { Write-Output $output }
	}
}

# Connect to Azure
try {
	Write-Log "Logging in to Azure using Managed Identity..." -Level Info
	$null = Connect-AzAccount -Identity -ErrorAction Stop
    
	$context = Get-AzContext
	Write-Log "Successfully connected to subscription: $($context.Subscription.Name) ($($context.Subscription.Id))" -Level Info
}
catch {
	Write-Log "Failed to connect to Azure: $($_.Exception.Message)" -Level Error
	throw
}

# Warn that deletion mode is active
Write-Log "========================================" -Level Warning
Write-Log "⚠️  DELETION MODE ACTIVE ⚠️" -Level Warning
Write-Log "This will PERMANENTLY DELETE resource groups!" -Level Warning
Write-Log "========================================" -Level Warning

# Initialize tracking arrays
[System.Collections.ArrayList]$resourceGroupsKept = @()
[System.Collections.ArrayList]$resourceGroupsDeleted = @()
[System.Collections.ArrayList]$deletionJobs = @()

# Constants
$TAG_KEY_NAME = "keepIt"
$TAG_KEEP_VALUE = "true"

try {
	# Get all resource groups
	Write-Log "Retrieving all resource groups..." -Level Info
	$resourceGroups = Get-AzResourceGroup -ErrorAction Stop
	Write-Log "Found $($resourceGroups.Count) resource group(s) to evaluate" -Level Info
    
	foreach ($rg in $resourceGroups) {
		$rgName = $rg.ResourceGroupName
		$shouldDelete = $true  # Default: delete unless keepIt=true
		$reason = ""
		$tagKeyActual = $TAG_KEY_NAME  # Store the actual tag key name found
        
		Write-Log "Evaluating resource group: '$rgName'" -Level Info
        
		# Check if resource group is in exclusion list
		if ($ExcludeResourceGroups -contains $rgName) {
			$shouldDelete = $false
			$reason = "Excluded by parameter"
			Write-Log "Resource group '$rgName' is in exclusion list" -Level Info
		}
		else {
			try {
				# Get tags for the resource group
				$tags = Get-AzTag -ResourceId $rg.ResourceId -ErrorAction Stop
				$existingTags = $tags.Properties.TagsProperty
                
				if ($null -eq $existingTags -or $existingTags.Count -eq 0) {
					$reason = "No tags present"
				}
				else {
					# Find the keepIt tag (case-insensitive)
					$keepItTag = $existingTags.GetEnumerator() | Where-Object { 
						$_.Key.ToLower() -eq $TAG_KEY_NAME.ToLower() 
					} | Select-Object -First 1
                    
					if ($null -eq $keepItTag) {
						$reason = "'$TAG_KEY_NAME' tag not found"
					}
					else {
						$tagKeyActual = $keepItTag.Key
						if ($keepItTag.Value -eq $TAG_KEEP_VALUE) {
							$shouldDelete = $false
							$reason = "'$tagKeyActual' = '$($keepItTag.Value)'"
						}
						else {
							$reason = "'$tagKeyActual' = '$($keepItTag.Value)' (not 'true')"
						}
					}
				}
			}
			catch {
				Write-Log "Error retrieving tags for '$rgName': $($_.Exception.Message)" -Level Warning
				$reason = "Error retrieving tags (will delete by default)"
			}
		}
        
		# Take action based on decision
		if ($shouldDelete) {
			Write-Log "WILL DELETE: '$rgName' - Reason: $reason" -Level Warning
			$null = $resourceGroupsDeleted.Add([PSCustomObject]@{
					Name     = $rgName
					Location = $rg.Location
					Reason   = $reason
				})
            
			try {
				Write-Log "Initiating deletion of resource group '$rgName'..." -Level Info
				$job = Remove-AzResourceGroup -Name $rgName -AsJob -Force -ErrorAction Stop
				$null = $deletionJobs.Add([PSCustomObject]@{
						ResourceGroupName = $rgName
						Job               = $job
					})
			}
			catch {
				Write-Log "Failed to start deletion job for '$rgName': $($_.Exception.Message)" -Level Error
			}
		}
		else {
			Write-Log "KEEPING: '$rgName' - Reason: $reason" -Level Info
			$null = $resourceGroupsKept.Add([PSCustomObject]@{
					Name     = $rgName
					Location = $rg.Location
					Reason   = $reason
				})
		}
	}
    
	# Monitor deletion jobs if requested
	if ($MonitorJobs -and $deletionJobs.Count -gt 0) {
		Write-Log "Monitoring $($deletionJobs.Count) deletion job(s)..." -Level Info
		Write-Log "This may take several minutes..." -Level Info
		Write-Log "Job timeout set to $JobTimeoutSeconds seconds per resource group" -Level Info
        
		foreach ($jobInfo in $deletionJobs) {
			try {
				$job = $jobInfo.Job
				$rgName = $jobInfo.ResourceGroupName
                
				Write-Log "Waiting for deletion of '$rgName' (Job ID: $($job.Id))..." -Level Info
				$result = $job | Wait-Job -Timeout $JobTimeoutSeconds
                
				if ($result.State -eq 'Completed') {
					Write-Log "✓ Successfully deleted resource group '$rgName'" -Level Info
				}
				elseif ($result.State -eq 'Failed') {
					$jobError = $result | Receive-Job -ErrorAction SilentlyContinue
					Write-Log "✗ Failed to delete resource group '$rgName': $jobError" -Level Error
				}
				else {
					Write-Log "⚠ Deletion job for '$rgName' did not complete in time (State: $($result.State))" -Level Warning
				}
                
				Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
			}
			catch {
				Write-Log "Error monitoring deletion job for '$($jobInfo.ResourceGroupName)': $($_.Exception.Message)" -Level Error
			}
		}
	}
	elseif ($deletionJobs.Count -gt 0 -and -not $MonitorJobs) {
		Write-Log "$($deletionJobs.Count) deletion job(s) initiated and running in background" -Level Info
		Write-Log "To monitor jobs, set -MonitorJobs `$true parameter" -Level Info
	}
}
catch {
	Write-Log "Unexpected error during execution: $($_.Exception.Message)" -Level Error
	throw
}
finally {
	# Output summary
	Write-Log "========================================" -Level Info
	Write-Log "EXECUTION SUMMARY" -Level Info
	Write-Log "========================================" -Level Info
    
	Write-Log "Resource Groups KEPT ($($resourceGroupsKept.Count)):" -Level Info
	if ($resourceGroupsKept.Count -eq 0) {
		Write-Log "  None" -Level Info
	}
	else {
		$resourceGroupsKept | ForEach-Object {
			Write-Log "  ✓ $($_.Name) [$($_.Location)] - $($_.Reason)" -Level Info
		}
	}
    
	Write-Log "Resource Groups DELETED ($($resourceGroupsDeleted.Count)):" -Level Info
	if ($resourceGroupsDeleted.Count -eq 0) {
		Write-Log "  None" -Level Info
	}
	else {
		$resourceGroupsDeleted | ForEach-Object {
			Write-Log "  ✗ $($_.Name) [$($_.Location)] - $($_.Reason)" -Level Info
		}
	}
    
	if (-not $MonitorJobs -and $deletionJobs.Count -gt 0) {
		Write-Log "*** Job monitoring was disabled - deletions are running in background ***" -Level Warning
		Write-Log "Check Azure Portal > Automation Account > Jobs to monitor progress" -Level Info
	}
    
	Write-Log "Execution completed at $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -Level Info
}