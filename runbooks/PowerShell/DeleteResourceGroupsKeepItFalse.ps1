try {
	"Logging in to Azure..."
	Connect-AzAccount -Identity
}
catch {
	Write-Error -Message $_.Exception
	throw $_.Exception
}

# Object arrays for later
[object[]]$objRGsKept = @()	# Resource groups that are kept and not deleted
[object[]]$objRGsDeleted = @() # Resource groups that are deleted

# Get all ARM resource groups
$ResourceGroups = Get-AzResourceGroup
$keyName = "keepIt"

foreach ($ResourceGroup in $ResourceGroups) {    
	# default setting is to disallow deletion
	$delete = $false

	Write-Output ("Retrieving tags of resource group '" + $ResourceGroup.ResourceGroupName + "'...")
	$tags = Get-AzTag -ResourceId $ResourceGroup.ResourceId
	$keys = $tags.Properties.TagsProperty.Keys
    
	# Tags are case-insensitive, we could have all kinds of cases, need to make sure it's there in any case
	if ($keys -contains $keyName) { 
		# keyName is an existing key, but we don't know the case yet
		#Write-Output ("'$keyName' exists for Resource group '" + $ResourceGroup.ResourceGroupName + "'.")

		# Retrieve the actual key name with its case
		$keyName = $keys | Where-Object { $_.ToLower() -eq $keyName.ToLower() }
		$value = $tags.Properties.TagsProperty.$keyName

		# if keepIt tag exists and is true, keep the resource group, otherwise delete it
		if ($value) {
			# keepIt tag exists and value is not empty
			if ($value -eq "true") {
				Write-Output ("Resource group '" + $ResourceGroup.ResourceGroupName + "' is kept ('$keyName' = '$value').")
				$objRGsKept += $ResourceGroup
			}
			else {
				# keepIt tag exists and has value 'false'
				Write-Output ("'$keyName' exists for Resource group '" + $ResourceGroup.ResourceGroupName + "' with value '$value'.")
				$delete = $true
			}
		}
	}
	else {
		# keepIt tag doesn't exist
		Write-Output ("'$keyName' doesn't exist for Resource group '" + $ResourceGroup.ResourceGroupName + "'.")
		$delete = $true
	}
	
	# Get list of resource groups to delete
	if ($delete -eq $true) {
		Write-Output ("Resource group '" + $ResourceGroup.ResourceGroupName + "' is deleted ('$keyName' = '$value').")
		$objRGsDeleted += $ResourceGroup 
		Remove-AzResourceGroup -Name $ResourceGroup.ResourceGroupName -AsJob -Force
	}

	Write-Output ("")
}

Write-Output ("SUMMARY")
Write-Output ("Resource groups kept:")
$objRGsKept | % { Write-Output $_.ResourceGroupName }
Write-Output ("")
Write-Output ("Resource groups deleted:")
$objRGsDeleted | % { Write-Output $_.ResourceGroupName }