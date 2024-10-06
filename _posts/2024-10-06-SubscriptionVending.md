---
title: Subscription Vending
description: Subscription Vending guide for Azure Landing Zones
author: Sebastian Claesson
date: 2024-10-06 00:55:00
categories: [Azure, Subscription vending]
tags: [powershell,azure,subscription,landing zone,vending,machine,vendingmachine,automation,permissions,ea,mca,rest]     # TAG names should always be lowercase
---

# Introduction
An important part of Azure Landing Zones is the ability to create Azure subscriptions (landing zones) through automation.

> Any scripts and code used in this post can be found at: https://github.com/SebastianClaesson/SubscriptionVendingExample
{: .prompt-tip }

## Enterprise Agreement Role Assignment for workload identities
There's an article on [Microsoft Learn](https://learn.microsoft.com/en-us/azure/cost-management-billing/manage/assign-roles-azure-service-principals#permissions-that-can-be-assigned-to-the-service-principal) that goes through how to assign a workload identity permissions to an Enterprise Agreement. 

If you are interested in following the least-privileged access model, then we must follow the article above to grant our workload identity access as "SubscriptionCreator" over our enrollment account.
The process of subscription vending must not be bound to a employees account or permissions.
However, not everyone is comfortable following the guide and takes short-cuts such as assigning Enterprise Administrator over the billing account using the IAM controls in Azure.

To assist with the creation of the EA Role assignment, I've created the following script [New-EnterpriseAgreementRoleAssignment](https://github.com/SebastianClaesson/SubscriptionVendingExample/blob/main/New-EnterpriseAgreementRoleAssignment.ps1)

Once the assignment has been done, we need to build our subscription vending automation somewhere.
This could be a Azure Function, GitHub/Azure DevOps Pipeline, Custom container or part of your self-service portal.

## Create your first Azure Subscription using PowerShell

The [Az.Subscription PowerShell module](https://www.powershellgallery.com/packages/Az.Subscription) contains the function "New-AzSubscriptionAlias" to provision a new Azure Subscription.

We can simply write a function to provision the subscription using our workload identity.
The function will run in the current logged in users context.

```powershell
[CmdletBinding()]
param (

    # BillingScope
    [Parameter(Mandatory)]
    [string]
    $BillingScope,

    # Workload
    [Parameter(Mandatory)]
    [string]
    $Workload,

    # ManagementGroupId
    [Parameter(Mandatory)]
    [string]
    $ManagementGroupId,

    # Identifier
    [Parameter(Mandatory)]
    [string]
    $Identifier,

    # Environment
    [Parameter(Mandatory)]
    [string]
    $EnvironmentShortName,

    # DisplayName
    [Parameter(Mandatory)]
    [string]
    $DisplayName
)

# The script requires the Az PowerShell Module
if (! (Get-Module 'Az.Subscription' -ListAvailable)) {
    Throw 'Please install the Az PowerShell Module "https://www.powershellgallery.com/packages/Az.Subscription"'
}

Import-Module .\Az.Subscription

$params = @{
    AliasName = "$Identifier-$EnvironmentShortName".toLower()
    SubscriptionName = "$DisplayName-$EnvironmentShortName".toLower()
    BillingScope = $BillingScope
    Workload = $Workload
    ManagementGroupId = $ManagementGroupId
}

Write-Verbose "Attempting to list any Azure Subscription" -Verbose
$SubAliases = Get-AzSubscriptionAlias
Write-verbose "Found a total of $($SubAliases.Count) Subscription Aliases." -Verbose
$SubAliases | Select-Object AliasName, SubscriptionId

if ($SubAliases.AliasName -Contains "$($params.AliasName)") {
    $SubscriptionInfo = $SubAliases | Where-Object {$_.AliasName -eq "$($params.AliasName)"}
    Write-Verbose "The subscription ""$($SubscriptionInfo.AliasName)"" already exists with id: '$($SubscriptionInfo.SubscriptionId)', Skipping creation." -Verbose
} else {
    try {
        $SubscriptionInfo = New-AzSubscriptionAlias @params
    
        Write-Output $SubscriptionInfo
    
        Write-verbose "Successfully created the subscription '$($SubscriptionInfo.AliasName)' with id: '$($SubscriptionInfo.SubscriptionId)'" -Verbose
    } catch {
        throw
    }
}
```

### Azure DevOps pipeline example
#### Configure Service Connection with Federated Credentials
To utilize Azure DevOps for our Workload identity, we need to configure [federated credentials](https://devblogs.microsoft.com/devops/workload-identity-federation-for-azure-deployments-is-now-generally-available/) to our workload identity.

This means we do not have to manage a client secret, instead we trust the Azure DevOps directory to manage the credentials to our workload identity.
As part of the service connection in Azure DevOps, we need to set a Azure Subscription where the pipeline initializes when running Azure PowerShell scripts.
This simply can be done by providing for example the [Reader](https://learn.microsoft.com/en-us/azure/role-based-access-control/built-in-roles/general#reader) role over a subscription.
> You must register the resource providers for Management Groups and Subscriptions to successfully run the automation in your initial subscription.
{: .prompt-tip }

To save time, We'll also create a script to manage the access and configuration of the service connection.

```powershell
## Requires the module ADOPS
function New-ADOServiceConnection {
    [CmdletBinding()]
    param (
        # SubscriptionId
        [Parameter(Mandatory)]
        [string]
        $SubscriptionId,

        # SubscriptionName
        [Parameter(Mandatory)]
        [string]
        $SubscriptionName,

        # Environment
        [Parameter(Mandatory)]
        [string]
        $Environment,

        # Identifier - This can be a project name, Service name or such to identify the Azure Landing Zone
        [Parameter(Mandatory)]
        [string]
        $Identifier,

        # Azure DevOps Organization
        [Parameter(Mandatory)]
        [string]
        $ADOOrganization,

        # Azure DevOps Project Name
        [Parameter(Mandatory)]
        [string]
        $ADOProjectName,

        # Role Defintion Name in Azure to be assigned to our Service Connection over the entire Landing Zone
        [Parameter(Mandatory)]
        [string]
        $RoleDefinitionName
    )
}

## Naming convention
$AppRegistrationName = "sc-azdo-$ProjectName-$Identifier-$Environment"
$ServiceConnectionName = "sc-$Identifier-$Environment"

# The script requires the Az PowerShell Module
if (! (Get-Module 'Az' -ListAvailable)) {
    Throw 'Please install the Az PowerShell Module "https://www.powershellgallery.com/packages/Az"'
}

# The script requires the ADOPS PowerShell Module
if (! (Get-Module 'ADOPS' -ListAvailable)) {
    Throw 'Please install the ADOPS PowerShell Module "https://www.powershellgallery.com/packages/ADOPS"'
}

# Check if the user is already logged in to the Az PowerShell Module.
$AzureContext = Get-AzContext
if (!$AzureContext) {
    # User is not logged into Az PowerShell Module
    Write-verbose "Please login to the Az PowerShell Module, this is used for confirming the existance of the Application Id and obtain an Azure Access Token" -Verbose
    Connect-AzAccount
}

$Description = "Federated Identity connection for Azure Subscription '$($AzureLandingZone.SubscriptionId)' as '$RoleDefinitionName'"

## Azure
$TenantId = $AzureContext.Tenant.Id

if ((Get-Module Az.Accounts).Version -lt '4.0.0') {
    $AccessToken = $(Get-AzAccessToken).Token
}
else {
    $AccessToken = $(Get-AzAccessToken).Token | ConvertFrom-SecureString -AsPlainText
}

# Verify that the Azure Landing zone exists.
$AzureLandingZone = Get-AzSubscription -SubscriptionId $SubscriptionId

# Connects to Azure DevOps
Connect-ADOPS -Organization $Organization -OAuthToken $AccessToken

# Gets the Azure DevOps project
$AzdoProject = Get-ADOPSProject -Name $ProjectName
if (!($AzdoProject)) {
    Get-ADOPSProject | Select-Object name, id | Sort-Object Name
    Throw "Unable to find $ProjectName"
}

# Gets the Azure DevOps Service Conection, if it already exists.
$AdopsSC = Get-ADOPSServiceConnection -Name $ServiceConnectionName -Project $ProjectName -IncludeFailed -ErrorAction SilentlyContinue
if (!($AdopsSC)) {
    $Params = @{
        TenantId = $TenantId 
        SubscriptionName = $SubscriptionName 
        SubscriptionId = $SubscriptionId 
        WorkloadIdentityFederation = $true
        Project = $ProjectName 
        ConnectionName = $ServiceConnectionName.ToLower()
        CreationMode = 'Manual'
        Description = $Description
    }
    $AdopsSC = New-ADOPSServiceConnection @Params
} else {
    Write-Verbose "Found '$ServiceConnectionName' in the Project $ProjectName" -Verbose
}

# Creates the Workload identity (Application Registration) using Az Module
$EntraIdAppParams = @{
    DisplayName = "$AppRegistrationName".tolower()
    Description = "Azure DevOps Service Connection used in '$ProjectName' for credential federation."
    Confirm = $false
}
$App = Get-AzADServicePrincipal -DisplayName $EntraIdAppParams.DisplayName
if (!($App)) {
    $App = New-AzADServicePrincipal -AccountEnabled @EntraIdAppParams
} else {
    Write-Verbose "The Entra ID Service Principal '$($App.DisplayName)' already exists." -Verbose
}
$AppDetails = Get-AzADApplication -ApplicationId $App.AppId

# Creates Entra Id Federated Credentials for authentication between Azure DevOps and Entra id using our Workload identity

$FederatedCreds = Get-AzADAppFederatedCredential -ApplicationObjectId $AppDetails.Id

if ($AdopsSC.authorization.parameters.workloadIdentityFederationSubject -in $FederatedCreds.Subject) {
    Write-Verbose "Azure DevOps Federated Credentials have already been configured." -Verbose
} else {
    $FederatedCredentialsParams = @{
        ApplicationObjectId = $AppDetails.Id
        Issuer = $AdopsSC.authorization.parameters.workloadIdentityFederationIssuer
        Subject = $AdopsSC.authorization.parameters.workloadIdentityFederationSubject
        Name = 'AzureDevOpsAuthentication'
        Description = "Azure DevOps Federated Credentials"
        Audience = 'api://AzureADTokenExchange'
    }
    New-AzADAppFederatedCredential @FederatedCredentialsParams
}

# Removes the default client secret
$Secret = Get-AzADAppCredential -ObjectId $AppDetails.Id
if ($Secret) {
    Remove-AzADAppCredential -KeyId $Secret.KeyId -ApplicationId $AppDetails.AppId
}

# Assigning correct permissions to Azure Landing Zone.
if (!(Get-AzRoleAssignment -Scope "/subscriptions/$($AzureLandingZone.SubscriptionId)" -RoleDefinitionName $RoleDefinitionName -ObjectId $App.Id)) {
    New-AzRoleAssignment -Scope "/subscriptions/$($AzureLandingZone.SubscriptionId)" -RoleDefinitionName $RoleDefinitionName -ObjectId $App.Id
} else {
    Write-Verbose "'$($App.Id)' already has access as '$RoleDefinitionName' over subscription '$($AzureLandingZone.SubscriptionId)'" -Verbose
}

# Completes the Service connection authentication details in Azure DevOps
$Params = @{
    TenantId = $TenantId
    SubscriptionName = $subscriptionName
    SubscriptionId = $subscriptionId
    Project = $ProjectName
    ServiceEndpointId = $AdopsSC.Id
    ConnectionName = $AdopsSC.name
    ServicePrincipalId = $App.AppId
    WorkloadIdentityFederationIssuer = $AdopsSC.authorization.parameters.workloadIdentityFederationIssuer
    WorkloadIdentityFederationSubject = $AdopsSC.authorization.parameters.workloadIdentityFederationSubject
    Description = $Description
}
Set-ADOPSServiceConnection @Params
```
#### Azure DevOps .yml example
Once this is done, we can write our Azure DevOps pipeline.
```yml
trigger: none
  
variables: 
- name: subscriptionCreationServiceConnection
  value: 'SERVICECONNECTIONNAME'

parameters:
- name: Identifier
  displayName: What is the identifying name of the Azure Landing Zone? (short name)
  type: string
- name: DisplayName
  displayName: What is the display name of the Azure Landing Zone? (long name)
  type: string
- name: ManagementGroupName
  displayName: Azure Management Group Name
  type: string
- name: BillingScope
  displayName: Azure Billing Scope, Example /billingAccounts/123456/enrollmentAccounts/123456
  type: string
- name: Workload
  displayName: Azure Subscription Workload offer - https://azure.microsoft.com/en-us/pricing/offers/dev-test
  type: string
  values: 
  - Production
  - DevTest
- name: Environment
  displayName: Environment?
  type: string
  default: Sandbox
  values:
  - sbx
  - dev
  - acc
  - prod

stages:
  - stage: provision
    displayName: 'Subscription Vending'
    jobs:
    - job: subscriptionCreate
      displayName: 'Create Azure Subscription'
      steps:
      - task: AzurePowerShell@5
        displayName: 'Create Azure Subscription'
        name: CreateSub
        inputs:
          azureSubscription: $(subscriptionCreationServiceConnection)
          ScriptType: 'FilePath'
          azurePowerShellVersion: LatestVersion
          pwsh: true
          ScriptPath: 'New-AzureSubscription.ps1'
          ScriptArguments: >
            -Identifier '$`\{`\{ parameters.Identifier `\}}'
            -BillingScope '$`\{{ parameters.BillingScope }}'
            -Workload 'Production'
            -ManagementGroupId '/providers/Microsoft.Management/managementGroups/${`\{ parameters.ManagementGroupName }}'
            -EnvironmentShortName '$(variableOutput.environmentShortName)'
            -DisplayName '${{ parameters.DisplayName }}'
```

After importing and running the Azure DevOps pipeline, the output should simply look like this:
![result](/assets/images/2024/10/DevOpsSubscriptionStatus.png)

## Conclusion

We have now established a workload identity to provision our Azure Subscriptions.
We have also created the nessecary automation & Azure DevOps pipeline to provide a basic self-service feature for our colleagues.

We can continue to add steps to our subscription vending, for example incorporating the orchestration of Entra Id security groups, privileged access management, entitlement management, IP address management, critical infrastructure resources such as peering to hub network, budgets, service health alerts and so on.

We're in the process of developing a Blazor website using MSAL to provide a modern UI.
This is hopefully something we can opensource in a near future, until then I hope this little post gave inspiration to your subscription vending process!

_References;_
- [_Subscription vending implementation guidance_](https://learn.microsoft.com/en-us/azure/architecture/landing-zones/subscription-vending)
- [_Subscription vending_](https://learn.microsoft.com/en-us/azure/cloud-adoption-framework/ready/landing-zone/design-area/subscription-vending)
