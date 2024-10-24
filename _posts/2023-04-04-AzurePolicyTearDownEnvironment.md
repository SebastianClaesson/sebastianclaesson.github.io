---
title: Azure policy to tear down environments
date: 2026-04-04 12:55:00
description: Azure policy to tear down environments
author: Sebastian Claesson
categories: [Azure DevOps, DevOps Agent]
tags: [powershell,azure,devops,extension,virtual machine,vmss,proxy,ubuntu]     # TAG names should always be lowercase
---

# Introduction
Azure policy is a great tool to control your environment, both for auditing purposes and for preventing/mitigating bad configuration of resources.
What could happen if your infrastructure/development department however configure a Azure policy wrong?
With the intention to tear-down or an attempt to hijack your Azure environment?
In this post, we'll try to see if we can use deplyoment scripts and other techniques to cause disruptions in our Azure environment.


## Deploy empty bicep template to resource group in complete mode. 
When reading through [Microsoft learn - Azure policy examples](https://learn.microsoft.com/en-us/azure/governance/policy/concepts/effect-deploy-if-not-exists#deployifnotexists-example) we can notice the section of our DeployIfNotExists example that we can set the deployment mode.
If you are familiar with Azure and different deployment modes, you are well aware of the two different modes that exists.
[Incremental mode](https://learn.microsoft.com/en-us/azure/azure-resource-manager/templates/deployment-modes#incremental-mode) which is the default mode, that only modifies/creates resources defined in your template, and leaves any undefined resources unchanged.
[Complete mode](https://learn.microsoft.com/en-us/azure/azure-resource-manager/templates/deployment-modes#complete-mode) that affects all resources over the scope you have select, even if they are defined or not within your template.

In our case, we would like to explore the feature of complete mode that if we deploy an empty resource group using Azure policies to any/all resources groups within a subscription - which the expected effect would be that any resources within these resource group(s) would be deleted.
The expected outcome would be something like this;
![result](/assets/images/2024/10/EmptyDeployment.png)

We define our Azure policy using bicep, setting deployment scope to subscription and deployment mode to Complete.
```bicep
targetScope = 'subscription'
resource policy 'Microsoft.Authorization/policyDefinitions@2023-04-01' = {
  name: 'DINE-emptyDeploymentCompleteMode'
  properties: {
    displayName: 'Empty Deployment in Complete mode.'
    policyType: 'Custom'
    mode: 'All'
    description: 'This policy will create an empty deployment in complete mode. This should delete any resources in that group if successful'
    metadata: {
      version: '1.0.0'
      category: 'BadConfiguration'
    }
    parameters: {
      effect: {
        type: 'String'
        defaultValue: 'DeployIfNotExists'
        metadata: {
          displayName: 'Effect'
          description: 'DeployIfNotExists, AuditIfNotExists or Disabled the execution of the Policy'
        }
        allowedValues: [
          'DeployIfNotExists'
          'AuditIfNotExists'
          'Disabled'
        ]
      }
    }
    policyRule: {
      if: {
        allOf: [
          {
            field: 'type'
            equals: 'Microsoft.Resources/resourceGroups'
          }
        ]
      }
      then: {
        effect: '[parameters(\'effect\')]'
        details: {
          type: 'Microsoft.Resources/ResourceGroups'
          roleDefinitionIds: [
            '8e3af657-a8ff-443c-a75c-2fe8c4bcb635'
          ]
          existenceCondition: {
            anyOf: [
              {
                field: 'type'
                equals: 'Microsoft.Resources/ResourceGroups'
              }
            ]
          }
          deployment: {
            properties: {
              mode: 'Complete'
              template: {
                schema: 'http://schema.management.azure.com/schemas/2015-01-01/deploymentTemplate.json#'
                parameters: {
                }
                variables: {}
                resources: []
              }
              parameters: {
              }
            }
          }
        }
      }
    }
  }
}
```

We then deploy our bicep to our Azure environment.
![result](/assets/images/2024/10/DeployCompleteError.png)
The deployment failed, as Azure will validate that the deployment mode is not set to complete.
This is great! It means we cannot utilize the deployment mode functionality to wipe resources.

## Deployment script with deletion.

## Fetch all information and dump on public storage account using copy backbone

## Overprivileged roles
Many of the builtin and community policies which uses the deploy if not exists use overprivileged roles.
Look at this table;
<Tavle of content with statistics of role and target resources>

The role itself will be inherited to your policy set (initiative) and could be used by a policy to gain access.

# Copy data using backbone
# Leak SAS tokens
# Leak VPN IP and shared key

## Policy lifecycle tools
- AzOps
- Enterprise Policy As Code
- Azure landing zone repo
