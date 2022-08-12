---
title: PowerShell Azure Functions
date: 2022-08-11 14:55:01
categories: [Azure, FunctionApp]
tags: [powershell,azure,alert,queue,table]     # TAG names should always be lowercase
---

I've been playing around a little with Azure Functions and Azure Alerting.
The design was to be able to utilize the Azure Alert rule processing function in Azure and have it create a prettier mail than what comes out of box.

Basically the design boiled down to having a few Azure Functions, A Storage Account with Tables and Queues a long with some PowerShell Magic :)

First of all we'll need a Function app with a managed identity.
For this project I've decided to use a System Assigned identity for my Function app.

I'll deploy a bicep with the following settings to my Function app:

```
resource functionAppSettings 'Microsoft.Web/sites/config@2020-06-01' = {
  parent: functionApp
  name: 'appsettings'
  properties: {
    APPLICATIONINSIGHTS_CONNECTION_STRING: reference(appInsights.id, '2020-02-02').ConnectionString
    AzureWebJobsDisableHomepage: 'true'
    AzureWebJobsSecretStorageKeyVaultUri: keyvault.properties.vaultUri
    AzureWebJobsSecretStorageType: 'keyvault'
    AzureWebJobsStorage__accountName: storageAccount.name
    FUNCTIONS_APP_EDIT_MODE: 'readonly'
    StorageQueueConnection__credential: 'managedidentity'
    StorageQueueConnection__queueServiceUri: storageAccount.properties.primaryEndpoints.queue
    WEBSITE_RUN_FROM_PACKAGE: '1'
    FUNCTIONS_WORKER_RUNTIME: 'powershell'
    FUNCTIONS_EXTENSION_VERSION: '~4'
  }
}
```

With these app settings my function app will now:
1) Store secrets in keyvault (such as the master/function keys) using the managed identity.
2) Create a Storage queue connection object that will use my Storage Accounts queue endpoint and connect to that using the managed identity.

In order to have the keyvault integration, you'll need to assign the correct permissions for the identity to read/write secrets.
This can be acheived with bicep, powershell or az cli.

Once the infrastructure is in place, you can now create the structure for your function app.
If you're familiar with function bindings, this will be easy.
However, if you are not familiar with it, I suggest reading about it at <hereurl>.

_Brief explaination of the bindings._
You can specify both in- and output bindings.
There's precompiled bindings that you can use from the open source community or used by the function runtime bundle.
Read more about the runtime bundle <here>.

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

As you can see there's a queueTrigger called "QueueItem".
It also has a queueName, which is the Storage Accounts queue name and a connection name.
My function will use the StorageQueueConnection "object" in my function app settings, as we specified in the bicep above.
The "object" can contain several settings, which you can read more about here <urlForAppSettingsManagedIdentityConnections>.

As you can see, I have no App Setting called "StorageQueueConnection", however I do have the following configuration:
```
    StorageQueueConnection__credential: 'managedidentity'
    StorageQueueConnection__queueServiceUri: storageAccount.properties.primaryEndpoints.queue
```

When the runtime is running a sync cycle, it will try and parse my settings that is prefixed with "StorageQueueConnection" and followed by two underscores.
In my case, it will try to connect to my Azure Storage Account Queue endpoint using the Function app managed identity.

_In order for this to work, you'll have to make sure that the managed identity has at least the Storage Queue Data Contributor role._

The configuration for the Azure Storage Account Queue settings can be set in the host.json file for the Function app.
For our Function app, we'll use the following configuration:
```json
{
  "version": "2.0",
  "extensionBundle": {
    "id": "Microsoft.Azure.Functions.ExtensionBundle",
    "version": "[3.11.0, 4.0.0)"
  },
  "extensions": {
    "queues": {
      "maxPollingInterval": "00:00:02",
      "visibilityTimeout": "00:00:30",
      "batchSize": 5,
      "maxDequeueCount": 5,
      "newBatchThreshold": 8,
      "messageEncoding": "base64"
    }
  }
}
```

This will configure our app to check the queue every 2 second.
More about this can be found here <url to read about extension settings>.

After adding some PowerShell magic to our function app it will now parse the data passed down by the queue to the function.
```PowerShell
using namespace System.Net
# Input bindings are passed in via param block.
param($QueueItem, $TriggerMetadata)
Write-Information "Queue item insertion time: $($TriggerMetadata.InsertionTime)"
Write-Information $QueueItem
```

_The parameter must match the name set in the function.json file, in our case 'QueueItem'_
This PowerShell script will only output the insertion time and the data of the message found in the queue.

We will make it more interesting in our case, and add a new output binding for SendGrid.
To enable the output binding for SendGrid we will have to go back to our function.json file and add the following rows:

```Json
{
  "bindings": [
    {
      "name": "QueueItem",
      "type": "queueTrigger",
      "direction": "in",
      "queueName": "sendgrid",
      "connection": "StorageQueueConnection"
    },
    {
      "type": "sendGrid",
      "direction": "out",
      "name": "message",
      "apikey": "<input api key>"
    }
  ]
}
```
Now as you can see, we have added a new output binding of the type sendGrid in the out direction.
We'll give it the name message.
To understand how the sendGrid output binding works, we can read the help docs at <SendGridHelpDocs>.
To get your API key you can read more here: <SendGridApiKey>.
I strongly suggest that you keep this secret inside of an Azure Keyvault and have a reference to it inside your function app setting.

But to keep it short, we'll add the following code to our PowerShell script.

```PowerShell
$mail = @{
    "personalizations" = @(
        @{
            "to" = @(@{"email" = "user@contoso.com"})
        }
    )
    "from"             = @{ 
        "email" = "user@contoso.com"
    }        
    "subject"          = "New message!"
    "content"          = @(
        @{
            "value" = "A new message as put on the queue!"
        }
    )
}
# Send the email using the output binding for SendGrid.
Push-OutputBinding -Name message -Value (ConvertTo-Json -InputObject $mail -Depth 100) 
```

Now the output binding will try to send an api call to SendGrid with our message.
The simple message will look like this:

<Picture>

To make it more advanced you can also send a html file, if you like to make pretty e-mails :)

Thank you for reading and hopefully my notes will be found useful!
Feel free to leave feedback either here on my blog or directly to me at any professional social media platform of your choosing.

//Sebastian
