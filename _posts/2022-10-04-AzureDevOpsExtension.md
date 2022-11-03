---
title: Azure DevOps Pipeline Agent Extension - Looking under the hood.
date: 2023-10-04 17:55:00
categories: [Azure, AzureDevOps]
tags: [powershell,azure,devops,extension,virtual machine,vmss,proxy]     # TAG names should always be lowercase
---

Along with [Björn Sundling](https://bjompen.com/#/) we decided to team up to try and figure out how the [Azure DevOps Pipeline Agent Extension](https://learn.microsoft.com/en-us/azure/devops/pipelines/release/deployment-groups/howto-provision-deployment-group-agents?view=azure-devops) in Azure works, and the different ways of installing the Pipeline agent and configuring settings for it.

We start by following the example provided on [docs](https://learn.microsoft.com/en-us/azure/devops/pipelines/release/deployment-groups/howto-provision-deployment-group-agents?view=azure-devops#install-the-azure-pipelines-agent-azure-vm-extension-using-an-arm-template) to see how we can configure the Azure VM Extension.

> Note that in the example ARM file a Personal Access Token (PAT) is required under the protected settings. You should never share your PAT with anyone and always keep it protected.
{: .prompt-info }

The log file @ C:\WindowsAzure\Logs\Plugins\Microsoft.VisualStudio.Services.TeamServicesAgent\1.29.0.0\RMExtensionHandler.1.20221004-131452 writes a log that confirms our settings.
The extension also puts a scheduled task 

Using the following bicep template to deploy 

Paths:
C:\Packages\Plugins\Microsoft.VisualStudio.Services.TeamServicesAgent\1.29.0.0\bin
Defaults to  C:\a
In my case: C:\agent
C:\WindowsAzure

Cloud Init - Tjänst som varje resurs i azure har en webtjänst på ett loopback interface.
För att få azure metadata service.
Azure Metadata Service for WIndows


> The bicep file is not complete and is missing resources such as role assignments etc. This just a demonstration of how to set the application settings.
{: .prompt-info }

Once the infrastructure is in place, you can now create the structure for your function app.
If you're familiar with zip deployments/function bindings, this will be easy.
However, if you are not familiar with it, I suggest reading about it at [Zip-deploy](https://docs.microsoft.com/en-us/azure/azure-functions/deployment-zip-push) & [Function Triggers and Bindings](https://docs.microsoft.com/en-us/azure/azure-functions/functions-triggers-bindings?tabs=powershell).

**_Brief explaination of the triggers/bindings._**

_You can specify both in- and output bindings.
There's bindings that you can use from the open source community or included in the function runtime.
Read more about the runtime [extension bundle](https://docs.microsoft.com/en-us/azure/azure-functions/functions-bindings-register#extension-bundles)._

In my scenario, I'll create a input binding that uses the Azure Storage Queue trigger.
For my function it will have a function.json in it's folder, containing the following configuration:
```json
{
  "bindings": [
    {
      "name": "QueueItem",
      "type": "queueTrigger",
      "direction": "in",
      "queueName": "sendgrid",
      "connection": "StorageQueueConnection"
    }
  ]
}
```

![simple-mail](/assets/images/2022/2022-08-16-1.png)

To make it more advanced you can also send a html file, in my case I'll use a html template file with some placeholders which we'll search and replace during runtime and using the information passed down by the message.
Simply change the change the content-type to "text/html" when posting to the output binding, if you like pretty mails :)

![html-mail](/assets/images/2022/2022-08-16-2.png)

Thank you for reading and hopefully my notes will be found useful!

//Sebastian
