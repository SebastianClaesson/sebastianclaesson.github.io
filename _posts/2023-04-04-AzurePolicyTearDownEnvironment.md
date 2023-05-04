---
title: Azure policy to tear down environments
date: 2025-04-04 12:55:00
categories: [Azure DevOps, DevOps Agent]
tags: [powershell,azure,devops,extension,virtual machine,vmss,proxy,ubuntu]     # TAG names should always be lowercase
---

# Introduction
Azure policy is a great tool to control your environment, both for auditing purposes but also for preventing/mitigating bad configuration of resources.
What could happen if your infrastructure/development department however configure a Azure policy wrong? Or with the intention to tear-down or an attempt to hijack your Azure environment?
In this post, we'll try to see if we can use deplyoment scripts and other techniques to cause disruptions in our Azure environment.


## Deploy if not exists
We'll try to use the deployIfNotExists method of an Azure policy, that will target any resource group without a storage account.
It will try to remidiate the resource group by doing a complete deployment with an empty template.
[Complete mode](https://learn.microsoft.com/en-us/azure/azure-resource-manager/templates/deployment-modes#complete-mode) means that the resource group will delete any Azure resources that's not defined in the deployment.