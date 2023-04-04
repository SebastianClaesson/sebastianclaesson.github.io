---
title: Azure AD Cross-tenant Collaboration / VNET Cross-tenant peering
date: 2023-04-04 12:55:00
categories: [Azure DevOps, DevOps Agent]
tags: [powershell,azure,devops,extension,virtual machine,vmss,proxy,ubuntu]     # TAG names should always be lowercase
---

The possibility to create Virtual network peerings across Azure Active Directory tenants has been available since 2018. \
It's a feature which is allowed by default and is quite easy to setup and get started with. \
It helps provide private networking between two Azure AD tenants subscriptions and can be an alternative to private link/private endpoints etc. \
This post will go through the setup and requirements, but also how you can detect cross-tenant collaboration & blocking it. \
I will not deep-dive into all the toolings around it, such as Conditional access or other features you get available by using a [Azure AD Premium subscription](https://learn.microsoft.com/en-us/azure/active-directory/authentication/concept-mfa-licensing).

Tenant A is a new Tenant, out-of-box, with no customization done to External collaboration settings.
Out of box, external collaboration settings:
![Tenant A - External Collaboration](/assets/images/2023/SourceGuestSettings.png) \
This means that anyone in the Tenant A organization can invite guest users and that it may be sent to any domain. \
If we head over to Cross-tenant access settings, we can also see that B2B collaboration access settings are allowed both inbound and outbound. \
Reference: [Cross-tenant access settings](https://learn.microsoft.com/en-us/azure/active-directory/external-identities/cross-tenant-access-overview#default-settings) \
We attempt to reach the Azure AD Tenant A from the user in Tenant B, without being invited as a guest to that tenant.

![Tenant B to Tenant A - External Collaboration attempt 1](/assets/images/2023/TenantBInteractionWithoutInvitation.png)

If you are inviting a user that does not have an E-mail address, you can use for example PowerShell to create and consume an invitation.\
_Reference: [Invite guest user - PowerShell](https://learn.microsoft.com/en-us/azure/active-directory/external-identities/b2b-quickstart-invite-powershell)_

```powershell
$params = @{
    InvitedUserDisplayName = "Sebastian Guest user"
    InvitedUserEmailAddress = "sebastian.claesson@contoso.com"
    InviteRedirectUrl = "https://myapplications.microsoft.com"
    SendInvitationMessage = $false
}
$Invite = New-MgInvitation @params

$invite | select Id, InviteRedeemUrl, InvitedUserDisplayName, InvitedUserEmailAddress, InvitedUserType, Status, @{'n'='UserId';'E'={$_.InvitedUser.Id}} | ConvertTo-Json | clip
```

The response from the invitation is as following:
```json
{
  "Id": "51b5db20-6630-4776-a183-288f78dff904",
  "InviteRedeemUrl": "https://login.microsoftonline.com/redeem?rd=https%3a%2f%2finvitations.microsoft.com%2fredeem%2f%3ftenant%3d31ca78c2-d833-433a-9977-88e160bd4ac0%26user%3d51b5db20-6630-4776-a183-288f78dff904%26ticket%3dHq53w18dK78ZhChJlhx37EDD9i3xIQBIUc9uDoqurwQ%25253d%26ver%3d2.0",
  "InvitedUserDisplayName": "Sebastian Guest user",
  "InvitedUserEmailAddress": "sebastian.claesson@contoso.com",
  "InvitedUserType": "Guest",
  "Status": "PendingAcceptance",
  "UserId": "a9cf0759-4de1-4ee2-85a6-47ff8f4e34f0"
}
```

Once we consume the InviteRedeemUrl, we simply go to the invited user's context and browse to the link.

![Tenant B User consumes invitation](/assets/images/2023/TenantBInvitationRedeemProcess.png)

Once the invitation has been accepted, we can verify that the user has been created in Tenant A by running
```powershell
Get-MgUser -userId $Invite.InvitedUser.Id

# Output
Id                : a9cf0759-4de1-4ee2-85a6-47ff8f4e34f0
DisplayName       : Sebastian Claesson
UserPrincipalName : sebastian.claesson_contoso.com#EXT#@tenantA.onmicrosoft.com
```

## Lets try to establish a network peering from Tenant B to Tenant A using the Portal experience.
![Tenant B Peering attempt](/assets/images/2023/TenantBtoTenantAPeerAttempt1.png)
We receive the error:
```plain
Failed to add virtual network peering 'TenantB2TenantA' to 'vnet-demo-test'. 
Error: The client 'sebastian.claesson@contoso.com' with object id '30d70e94-10e8-494d-bece-ea990d773b47' has permission to perform action 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings/write' on scope 'demo-test-rg/providers/Microsoft.Network/virtualNetworks/vnet-demo-test/virtualNetworkPeerings/TenantB2TenantA' > vnet-demo-test/TenantB2TenantA'; 
however, it does not have permission to perform action 'peer/action' on the linked scope(s) '/subscriptions/8655f4d3-0bb1-4be0-b73c-6a8f3b304cf6/resourceGroups/demo-rg/providers/Microsoft.Network/virtualNetworks/demo-vnet' or the linked scope(s) are invalid.
```
This means we're only invited as a guest with no Azure Resource access in target subscription. \
We'll assign our Tenant B user the role of "Network Contributor" in the correct subscription of Tenant A and make a new attempt. \
To confirm that the peering has been initiated we can run the following command:

```powershell
Get-AzVirtualNetworkPeering -VirtualNetworkName "vnet-demo-test" -ResourceGroupName "demo-test-rg" | 
Select Name, @{'N'='RemoteVnetId';'E'={$_.RemoteVirtualNetwork.Id}}, PeeringSyncLevel, PeeringState, ProvisioningState | fl

Name              : TenantB2TenantA
RemoteVnetId      : /subscriptions/8655f4d3-0bb1-4be0-b73c-6a8f3b304cf6/resourceGroups/demo-rg/providers/Microsoft.Network/virtualNetworks/demo-vnet
PeeringSyncLevel  : RemoteNotInSync
PeeringState      : Initiated
ProvisioningState : Succeeded
```
As indicated, the peering has been initiated, however not completed.\
When checking the status of the remote virtual network we are trying to peer with, we can see that there's been no peering created.
![Tenant A Peerings](/assets/images/2023/TenantAVnetPeerStatus.png)
This means we'll have to estalish a peer from Tenant A to Tenant B.\
The easiest way is simply to change tenant in the invited user's context and establish the peering using the portal experience.\
To confirm a successful peering, we can run the following PowerShell command
```powershell
Get-AzVirtualNetworkPeering -VirtualNetworkName 'demo-vnet' -ResourceGroupName 'demo-rg' | 
Select Name, @{'N'='RemoteVnetId';'E'={$_.RemoteVirtualNetwork.Id}},  @{'N'='RemoteVirtualNetworkAddressSpace';'E'={$_.RemoteVirtualNetworkAddressSpace.AddressPrefixes}}, PeeringSyncLevel, PeeringState, ProvisioningState | fl

# Output
Name                             : TenantA2TenantB
RemoteVnetId                     : /subscriptions/31bdf544-8e8e-4f5b-bb31-3316a05e5581/resourceGroups/demo-test-rg/providers/Microsoft.Network/virtualNetworks/vnet-demo-test
RemoteVirtualNetworkAddressSpace : 192.168.1.0/24
PeeringSyncLevel                 : FullyInSync
PeeringState                     : Connected
ProvisioningState                : Succeeded

Get-AzVirtualNetworkPeering -VirtualNetworkName "vnet-demo-test" -ResourceGroupName "demo-test-rg" | Select Name, @{'N'='RemoteVnetId';'E'={$_.RemoteVirtualNetwork.Id}}, @{'N'='RemoteVirtualNetworkAddressSpace';'E'={$_.RemoteVirtualNetworkAddressSpace.AddressPrefixes}}, PeeringSyncLevel, PeeringState, ProvisioningState | fl

Name                             : TenantB2TenantA
RemoteVnetId                     : /subscriptions/8655f4d3-0bb1-4be0-b73c-6a8f3b304cf6/resourceGroups/demo-rg/providers/Microsoft.Network/virtualNetworks/demo-vnet
RemoteVirtualNetworkAddressSpace : 10.0.0.0/16
PeeringSyncLevel                 : FullyInSync
PeeringState                     : Connected
ProvisioningState                : Succeeded
```

Here we can confirm that the peering between the tenants have been established successfully.\
These networks can now access each other and routes has been presented by the peer, as seen in the following screenshot on a NIC inside Tenant B.
![Tenant B VM Routes](/assets/images/2023/TenantBVMRoutes.png)

# How do we protect our Organization for cross-tenant collaboration?
You might ask yourself "How do we protect our employees/organization from accidently allowing cross-tenant virtual network peerings to prevent data exfiltration or network communication by-passing the VNA?".\
There are different ways to enforce and detect this, however, if we assume that Tenant B is a organization which has adopted the Landing Zone concept, we know that our developers/users have access to modify route tables etc. to manage their LZ. \
In this part we'll focus on how we can prevent cross-tenant collaboration. \
We'll have to go back to the Cross-tenant access settings, specfically the Inbound and Outbound B2B collaboration settings.

> Note: B2B collaboration settings are not only limited to Azure resource actions, and can include Office 365 and other services.\
Reference: [Azure AD B2B Collaboration](https://learn.microsoft.com/en-us/azure/active-directory/external-identities/cross-tenant-access-settings-b2b-collaboration)
{: .prompt-info }

## Outbound blocked
If we set the Outbound access settings for B2B collaboration to "All blocked", we can still establish a network peering by following the procedure above.

## Inbound blocked
If we set the Inbound access settings for B2B collaboration to "All blocked", we are unable to establish a peer from Tenant B to Tenant A. 

![Tenant A blocking inbound](/assets/images/2023/TenantAPeeringWithTenantBBlockingMessage.png)

We are also unable to login towards the tenant without guest user account. \
Receiving the error message above, also with the detailed error "AADSTS500213: The resource tenant's cross-tenant access policy does not allow this user to access this tenant."

## Detection

There's a workbook published in Azure AD that you can utilize if logs are streamed to a log analytics workspace.
It's called "[Cross-tenant access activity](https://learn.microsoft.com/en-us/azure/active-directory/reports-monitoring/workbook-cross-tenant-access-activity)" 

To get a bit more in-depth data on the activity, you can simply take a snippet out of the query such as:
```kql
SigninLogs
    | project TimeGenerated,
        UserPrincipalName,
        HomeTenantId,
        AADTenantId,
        Id,
        ResourceTenantId,
        ResourceDisplayName,
        ResourceIdentity,
        Status,
        UserType,
        UserId
    | where UserId != "00000000-0000-0000-0000-000000000000"
    | where ResourceIdentity != ''
    | where "All users" == "All users" or UserPrincipalName has "All users"
    | where "All applications" == "All applications" or ResourceDisplayName has "All applications"
    | where "All external tenants" == "All external tenants" or HomeTenantId has "All external tenants"
    | where HomeTenantId != ''
    | where HomeTenantId != AADTenantId
    | extend status = case(Status.errorCode == 0, "Success", "Failure")
    | where "All" == status or "All" == "All"
```
Now you'll visualize each request and you are able to identify each tenant that your users are interacting with.
![Dataset](/assets/images/2023/kqlexample.png)

# Summary
It's a good idea to keep track of possible cross-tenant integrations, may it be using virtual network peerings / private links / private endpoints or by using service endpoints.
This post only covers some of these points and how it can be prevented using other methods than Azure policy or Azure monitor/alert.