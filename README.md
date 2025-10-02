# azure-automation

Components for Azure Automation Runbooks

## Overview

This repository contains Azure Automation runbooks designed to help manage and automate Azure resource lifecycle management. The primary focus is on cost optimization and resource hygiene through automated cleanup of unused resources.

## Runbooks

### Delete Resource Groups (DeleteResourceGroupsKeepItFalse.ps1)

A PowerShell runbook that automatically deletes Azure Resource Groups that do not have a `keepIt` tag set to `true`. This helps maintain a clean Azure environment and reduces costs by removing unused or temporary resource groups.

#### Features

- ✅ **Safety-First Design**: Disabled by default with explicit activation required
- ✅ **Tag-Based Protection**: Resource groups with `keepIt=true` are preserved
- ✅ **Flexible Execution**: Fire-and-forget or monitored deletion modes
- ✅ **Customizable Timeout**: Configurable job timeout for deletion operations
- ✅ **Exclusion List**: Ability to exclude specific resource groups by name
- ✅ **Detailed Logging**: Structured output with timestamps and levels
- ✅ **Job Tracking**: Optional monitoring of deletion job completion
- ✅ **Managed Identity**: Uses Azure Automation Managed Identity (no stored credentials)

#### How It Works

The runbook evaluates each resource group based on the following logic:

| Scenario               | Action     | Description                                      |
| ---------------------- | ---------- | ------------------------------------------------ |
| `keepIt` tag = `true`  | **KEEP**   | Resource group is explicitly protected           |
| `keepIt` tag = `false` | **DELETE** | Resource group explicitly marked for deletion    |
| `keepIt` tag missing   | **DELETE** | Default behavior is to delete untagged resources |
| No tags at all         | **DELETE** | Default behavior is to delete untagged resources |
| In exclusion list      | **KEEP**   | Resource group excluded via parameter            |

> **Note**: Tag matching is case-insensitive (`keepIt`, `KeepIt`, `KEEPIT` all work)

## Prerequisites

### Azure Resources

1. **Azure Automation Account** with System-assigned Managed Identity enabled
2. **Managed Identity Permissions**: The identity needs one of the following roles on the subscription:
   - `Contributor`
   - `Owner`
   - Custom role with permissions:
     - `Microsoft.Resources/subscriptions/resourceGroups/read`
     - `Microsoft.Resources/subscriptions/resourceGroups/delete`
     - `Microsoft.Resources/tags/read`

### PowerShell Modules

The following Az modules must be available in your Automation Account:

- `Az.Accounts` (>= 2.0.0)
- `Az.Resources` (>= 6.0.0)

## Quick Start

### 1. Create Automation Account

```powershell
# Create resource group for Automation Account
New-AzResourceGroup -Name "rg-automation" -Location "eastus"

# Create Automation Account with System-assigned Managed Identity
New-AzAutomationAccount `
    -Name "aa-resource-cleanup" `
    -ResourceGroupName "rg-automation" `
    -Location "eastus" `
    -AssignSystemIdentity
```

### 2. Assign Permissions

```powershell
# Get the Automation Account's Managed Identity
$automationAccount = Get-AzAutomationAccount `
    -ResourceGroupName "rg-automation" `
    -Name "aa-resource-cleanup"

$principalId = $automationAccount.Identity.PrincipalId

# Assign Contributor role at subscription level
$subscriptionId = (Get-AzContext).Subscription.Id

New-AzRoleAssignment `
    -ObjectId $principalId `
    -RoleDefinitionName "Contributor" `
    -Scope "/subscriptions/$subscriptionId"
```

### 3. Import Required Modules

```powershell
# Import Az.Accounts module
New-AzAutomationModule `
    -ResourceGroupName "rg-automation" `
    -AutomationAccountName "aa-resource-cleanup" `
    -Name "Az.Accounts" `
    -ContentLinkUri "https://www.powershellgallery.com/api/v2/package/Az.Accounts"

# Import Az.Resources module
New-AzAutomationModule `
    -ResourceGroupName "rg-automation" `
    -AutomationAccountName "aa-resource-cleanup" `
    -Name "Az.Resources" `
    -ContentLinkUri "https://www.powershellgallery.com/api/v2/package/Az.Resources"
```

### 4. Import and Publish the Runbook

```powershell
# Import runbook
Import-AzAutomationRunbook `
    -ResourceGroupName "rg-automation" `
    -AutomationAccountName "aa-resource-cleanup" `
    -Path ".\runbooks\PowerShell\DeleteResourceGroupsKeepItFalse.ps1" `
    -Type PowerShell `
    -Name "Delete-UntaggedResourceGroups"

# Publish runbook
Publish-AzAutomationRunbook `
    -ResourceGroupName "rg-automation" `
    -AutomationAccountName "aa-resource-cleanup" `
    -Name "Delete-UntaggedResourceGroups"
```

### 5. Schedule the Runbook (Optional)

```powershell
# Create a schedule to run daily at 2 AM UTC
New-AzAutomationSchedule `
    -ResourceGroupName "rg-automation" `
    -AutomationAccountName "aa-resource-cleanup" `
    -Name "DailyCleanup" `
    -StartTime (Get-Date "02:00:00").AddDays(1) `
    -DayInterval 1

# Link the schedule to the runbook with parameters
Register-AzAutomationScheduledRunbook `
    -ResourceGroupName "rg-automation" `
    -AutomationAccountName "aa-resource-cleanup" `
    -RunbookName "Delete-UntaggedResourceGroups" `
    -ScheduleName "DailyCleanup" `
    -Parameters @{ EnableDeletion = $true }
```

## Usage

### Protecting Resource Groups

To protect a resource group from deletion, add the `keepIt` tag with value `true`:

**Via Azure Portal:**

1. Navigate to the resource group
2. Go to **Tags**
3. Add tag: `keepIt` = `true`
4. Click **Save**

**Via Azure CLI:**

```bash
az group update --name <resource-group-name> --set tags.keepIt=true
```

**Via PowerShell:**

```powershell
Set-AzResourceGroup -Name "<resource-group-name>" -Tag @{ keepIt = "true" }
```

### Running the Runbook

#### First Run (Will Be Blocked)

```powershell
# This will show a warning and exit - safety mechanism
Start-AzAutomationRunbook `
    -ResourceGroupName "rg-automation" `
    -AutomationAccountName "aa-resource-cleanup" `
    -Name "Delete-UntaggedResourceGroups"
```

#### Production Run (Fire and Forget)

```powershell
Start-AzAutomationRunbook `
    -ResourceGroupName "rg-automation" `
    -AutomationAccountName "aa-resource-cleanup" `
    -Name "Delete-UntaggedResourceGroups" `
    -Parameters @{ EnableDeletion = $true }
```

#### Production Run with Job Monitoring

```powershell
Start-AzAutomationRunbook `
    -ResourceGroupName "rg-automation" `
    -AutomationAccountName "aa-resource-cleanup" `
    -Name "Delete-UntaggedResourceGroups" `
    -Parameters @{
        EnableDeletion = $true
        MonitorJobs = $true
        JobTimeoutSeconds = 120
    }
```

#### Excluding Specific Resource Groups

```powershell
Start-AzAutomationRunbook `
    -ResourceGroupName "rg-automation" `
    -AutomationAccountName "aa-resource-cleanup" `
    -Name "Delete-UntaggedResourceGroups" `
    -Parameters @{
        EnableDeletion = $true
        ExcludeResourceGroups = @("NetworkWatcherRG", "DefaultResourceGroup-EUS")
    }
```

## Parameters

| Parameter               | Type     | Required | Default | Description                                                   |
| ----------------------- | -------- | -------- | ------- | ------------------------------------------------------------- |
| `EnableDeletion`        | bool     | No       | `false` | Must be set to `$true` to enable deletions. Safety mechanism. |
| `MonitorJobs`           | bool     | No       | `false` | Wait for all deletion jobs to complete before finishing.      |
| `JobTimeoutSeconds`     | int      | No       | `120`   | Timeout in seconds for each resource group deletion job.      |
| `ExcludeResourceGroups` | string[] | No       | `@()`   | Array of resource group names to exclude from deletion.       |

## Output Example

```
[2025-10-02 14:23:15] [Info] Logging in to Azure using Managed Identity...
[2025-10-02 14:23:18] [Info] Successfully connected to subscription: Production (12345678-1234-1234-1234-123456789abc)
[2025-10-02 14:23:19] [Warning] ========================================
[2025-10-02 14:23:19] [Warning] ⚠️  DELETION MODE ACTIVE ⚠️
[2025-10-02 14:23:19] [Warning] This will PERMANENTLY DELETE resource groups!
[2025-10-02 14:23:19] [Warning] ========================================
[2025-10-02 14:23:20] [Info] Found 15 resource group(s) to evaluate
[2025-10-02 14:23:21] [Info] Evaluating resource group: 'rg-production'
[2025-10-02 14:23:21] [Info] KEEPING: 'rg-production' - Reason: 'keepIt' = 'true'
[2025-10-02 14:23:22] [Info] Evaluating resource group: 'rg-temp-test'
[2025-10-02 14:23:22] [Warning] WILL DELETE: 'rg-temp-test' - Reason: 'keepIt' tag not found
...
========================================
EXECUTION SUMMARY
========================================

Resource Groups KEPT (3):
  ✓ rg-production [eastus] - 'keepIt' = 'true'
  ✓ rg-staging [westus] - 'keepIt' = 'true'
  ✓ rg-automation [eastus] - Excluded by parameter

Resource Groups DELETED (2):
  ✗ rg-temp-test [eastus] - 'keepIt' tag not found
  ✗ rg-old-demo [westus] - 'keepIt' = 'false' (not 'true')

Execution completed at 2025-10-02 14:25:30
```

## Best Practices

1. **🔒 Start with Safety First**: Always ensure critical resource groups have the `keepIt=true` tag before enabling the runbook
2. **📋 Use Exclusion Lists**: Add critical system resource groups (like NetworkWatcherRG) to the exclusion list
3. **⏰ Schedule Wisely**: Run during off-hours to minimize impact on active workloads
4. **📊 Monitor Regularly**: Review runbook job outputs in Azure Portal to ensure expected behavior
5. **🚨 Set Up Alerts**: Configure alerts for failed runbook executions
6. **🔐 Use Resource Locks**: For critical infrastructure, consider Azure Resource Locks as an additional safety layer
7. **📝 Audit Tags**: Periodically audit resource group tags to ensure they're correctly applied
8. **⏱️ Adjust Timeouts**: Tune `JobTimeoutSeconds` based on your resource group complexity and deletion times

## Troubleshooting

### Common Issues

**Issue**: Runbook fails with "Authentication failed"

- **Solution**: Ensure the Automation Account has System-assigned Managed Identity enabled and proper role assignments

**Issue**: Resource groups with `keepIt=true` are being deleted

- **Solution**: Verify the tag value is exactly `true` (lowercase) and not `True` or `TRUE`

**Issue**: Runbook times out

- **Solution**: Increase `JobTimeoutSeconds` parameter or disable `MonitorJobs` for fire-and-forget execution

**Issue**: Some resource groups aren't deleted even without tags

- **Solution**: Check if they're in the `ExcludeResourceGroups` parameter or if there are resource locks applied

### Viewing Logs

1. Navigate to your Automation Account in Azure Portal
2. Go to **Jobs**
3. Select the job you want to review
4. Click on **All Logs** to see detailed output

## Security Considerations

- ✅ Uses Managed Identity for authentication (no stored credentials)
- ⚠️ Deletion operations are permanent and cannot be undone
- 📋 Consider implementing Azure Policy to enforce tagging requirements
- 🔍 Regularly audit role assignments on the Managed Identity
- 📊 Use Azure Activity Log to track all deletion operations
- 🔒 Implement resource locks for mission-critical resource groups

## Contributing

Contributions are welcome! Please ensure:

- Code follows PowerShell best practices
- Changes are tested thoroughly
- Documentation is updated accordingly
- Commit messages are clear and descriptive

## License

See [LICENSE](LICENSE) file for details.

## Version History

- **v1.0** (Initial): Basic deletion logic with tag evaluation
- **v2.0** (Current):
  - Added safety activation flag (`EnableDeletion`)
  - Added optional job monitoring (`MonitorJobs`)
  - Added customizable timeout (`JobTimeoutSeconds`)
  - Added exclusion list support
  - Improved error handling and logging
  - Fixed variable scope issues
  - Enhanced output formatting

## Support

For issues or questions:

1. Review this documentation thoroughly
2. Check Azure Automation documentation: https://learn.microsoft.com/azure/automation/
3. Review runbook execution logs in Azure Portal
4. Open an issue in this repository with detailed information

## Related Resources

- [Azure Automation Documentation](https://learn.microsoft.com/azure/automation/)
- [Azure Resource Manager Tags](https://learn.microsoft.com/azure/azure-resource-manager/management/tag-resources)
- [Managed Identities for Azure Resources](https://learn.microsoft.com/azure/active-directory/managed-identities-azure-resources/)
- [Azure RBAC Documentation](https://learn.microsoft.com/azure/role-based-access-control/)

---

**⚠️ Warning**: This runbook performs destructive operations. Always test in a non-production environment first and ensure proper tagging of critical resources before deployment.
