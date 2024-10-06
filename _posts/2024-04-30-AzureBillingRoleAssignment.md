---
title: Azure Billing Role Assignments
date: 2025-04-04 12:55:00
categories: [Azure, Azure Billing]
tags: [powershell,azure,billing]     # TAG names should always be lowercase
---

# Introduction
We want to have a system user that is able to provision subscriptions as part of our vending machine.
There's currently no user interface to do this, only some preview apis from 2019.


## The code.

```Pwsh
[CmdletBinding()]
param (
    [Parameter(Mandatory)]
    [string]
    $IdentityId,

    # Role Defintion
    [Parameter(Mandatory)]
    [string]
    [ValidateSet('SubscriptionCreator', 'DepartmentReader', 'EA purchaser', 'EnrollmentReader')]
    $BillingRole
)

function Get-AzureBillingAccounts {
    [CmdletBinding()]
    param (
        # Headers
        [Parameter(Mandatory)]
        $Headers
    )
    $data = (Invoke-RestMethod -Method Get -Uri "https://management.azure.com/providers/Microsoft.Billing/billingAccounts?api-version=2019-10-01-preview" -Headers $Headers).value | 
    Select-Object Name, @{'N' = 'accountStatus'; 'E' = { $_.properties.accountStatus } }, @{'N' = 'agreementType'; 'E' = { $_.properties.agreementType } }, @{'N' = 'displayName'; 'E' = { $_.properties.displayName } }, Id
    Write-Output $data
}

function Get-AzureEnrollmentAccounts {
    [CmdletBinding()]
    param (
        # Billing Account Friendly Name
        [Parameter()]
        [string]
        $BillingAccountName,

        # Headers
        [Parameter(Mandatory)]
        $Headers
    )
    
    $data = (Invoke-RestMethod -Method Get -Uri "https://management.azure.com/providers/Microsoft.Billing/billingAccounts/$BillingAccountName/enrollmentAccounts?api-version=2019-10-01-preview" -Headers $Headers).value |
    Select-Object Name, @{'N' = 'AccountName'; 'E' = { $_.properties.accountName } }, @{'N' = 'CostCenter'; 'E' = { $_.properties.costCenter } }, @{'N' = 'DisplayName'; 'E' = { $_.properties.displayName } }, @{'N' = 'Status'; 'E' = { $_.properties.status } }, @{'N' = 'StartDate'; 'E' = { $_.Properties.startDate } }, @{'N' = 'EndDate'; 'E' = { $_.Properties.endDate } }
    Write-Output $data
}

function New-AzureBillingRoleAssignment {
    [CmdletBinding()]
    param (
        # Headers
        [Parameter(Mandatory)]
        $Headers,

        # Role Defintion
        [Parameter(Mandatory)]
        [string]
        [ValidateSet('SubscriptionCreator', 'DepartmentReader', 'EA purchaser', 'EnrollmentReader')]
        $BillingRole,

        # Identity
        [Parameter(Mandatory)]
        [string]
        $IdentityId,

        # Billing Account Name
        [Parameter(Mandatory)]
        [string]
        $BillingAccountName,

        # Enrollment Account Id
        [Parameter(Mandatory)]
        [string]
        $EnrollmentAccountName,

        # Tenant Id
        [Parameter(Mandatory)]
        [string]
        $TenantId
    )
    
    begin {
        # 'SubscriptionCreator' = 'a0bcee42-bf30-4d1b-926a-48d21664ef71'
        # 'DepartmentReader' = 'db609904-a47f-4794-9be8-9bd86fbffd8a'
        # 'EA purchaser' = 'da6647fb-7651-49ee-be91-c43c4877f0c4'
        # 'EnrollmentReader' = '24f8edb6-1668-4659-b5e2-40bb5f3a7d7e'
        # Reference; https://learn.microsoft.com/en-us/azure/cost-management-billing/manage/assign-roles-azure-service-principals#permissions-that-can-be-assigned-to-the-service-principal

        $BillingRoles = @{
            'SubscriptionCreator' = 'a0bcee42-bf30-4d1b-926a-48d21664ef71'
            'DepartmentReader'    = 'db609904-a47f-4794-9be8-9bd86fbffd8a'
            'EA purchaser'        = 'da6647fb-7651-49ee-be91-c43c4877f0c4'
            'EnrollmentReader'    = '24f8edb6-1668-4659-b5e2-40bb5f3a7d7e'
        }
        $BillingRoleId = $BillingRoles[$BillingRole]
    }
    
    process {
        # Generate a unique role assignment id.
        # https://learn.microsoft.com/en-us/azure/cost-management-billing/manage/assign-roles-azure-service-principals#assign-enrollment-account-role-permission-to-the-service-principal
        $UniqueRoleAssignmentId = (New-guid).Guid

        # Create a Role Assignment for our Workload Identity.
        $RoleAssignmentUrl = "https://management.azure.com/providers/Microsoft.Billing/billingAccounts/$BillingAccountName/enrollmentAccounts/$EnrollmentAccountName/billingRoleAssignments/$UniqueRoleAssignmentId`?api-version=2019-10-01-preview"
        $Body = @{
            "properties" = @{
                "principalId"       = "$IdentityId"
                "principalTenantId" = "$TenantId"
                "roleDefinitionId"  = "/providers/Microsoft.Billing/billingAccounts/$BillingAccountName/enrollmentAccounts/$EnrollmentAccountName/billingRoleDefinitions/$BillingRoleId"
            }
        } | ConvertTo-Json -depth 100

        try {
            Invoke-RestMethod -Method Put -Uri $RoleAssignmentUrl -Headers $Headers -Body $Body
            Write-verbose "Successfully create the role assignment." -Verbose
        }
        catch {
            throw
        }
    }
}

# The script requires the Az PowerShell Module
if (! (Get-Module 'Az' -ListAvailable)) {
    Throw 'Please install the Az PowerShell Module "https://www.powershellgallery.com/packages/Az"'
}

# Check if the user is already logged in to the Az PowerShell Module.
if (! (Get-AzContext -ListAvailable)) {
    # User is not logged into Az PowerShell Module
    Write-verbose "Please login to the Az PowerShell Module, this is used for confirming the existance of the Application Id and obtain an Azure Access Token" -Verbose
    Login-AzAccount
}

# Use the Access Token provided by Az PowerShell Module and create a header containing it.
$token = $(Get-AzAccessToken).Token
$headers = @{'Authorization' = "Bearer $Token"; 'Content-Type' = 'application/json' }

# Get Tenant Id
$TenantId = (get-azcontext).tenant.id

# Get Billing Account
$BillingAccount = Get-AzureBillingAccounts -Headers $headers | Out-GridView -PassThru
$BillingAccountName = $BillingAccount.Name

# Get Enrollment Account
$EnrollmentAccount = Get-AzureEnrollmentAccounts -BillingAccountName $BillingAccountName -Headers $headers | Out-GridView -PassThru

$Params = @{
    'Headers' = $headers 
    'BillingRole' = $BillingRole
    'IdentityId' = $IdentityId 
    'BillingAccountName' = $BillingAccountName 
    'EnrollmentAccountName' = $EnrollmentAccount.Name
    'TenantId' = $TenantId
}
New-AzureBillingRoleAssignment @Params
```