---
title: Azure DevOps Pipeline Agent Extension (Ubuntu) - Unauthenticated/Authenticated Proxy.
date: 2023-10-04 17:55:00
categories: [Azure, AzureDevOps]
tags: [powershell,azure,devops,extension,virtual machine,vmss,proxy,ubuntu]     # TAG names should always be lowercase
---

Do you want to provide a Azure Virtual Machine Scale-set template with a Azure DevOps agent that is using a web proxy that can be distributed between departments/teams?
Will your departments/teams not have access to deploy the agent from the Azure DevOps portal?
Are you looking to run your Azure DevOps agent behind a unauthenticated/authenticated web proxy for traffic destined to the internet?
Then hopefully this will be a good read for you :)

As a summary of how the installation and deployment of the Azure DevOps VM Extension:
1) VM/VMSS has the Azure DevOps Extension deployed to it.
2) The VM/VMSS will download the extension in a compressed format (zip) from a public Azure Storage Account.
3) The Extension will run the Handler.sh -enable command and run either AzureRM.py or AzureRM_Python2.py (depending on what Python version is available) to install the DevOps Agent.
4) AzureRM.py (or AzureRM_Python2.py) will read the settings file (containing the Public and Protected Settings), decrypt the protected settings with the computer certificate available and remove it from the settings file.
5) AzureRM.py will try to download the Azure DevOps agent zip file and EnableAgent script specified in the Public settings.
6) The InstallDependecies.sh script will use APT to install missing dependencies.
6) The Azure DevOps agent installation will start and configure itself according to the scenario specified.

The log locations for the Azure DevOps VM Extension are:
- /var/log/azure/Microsoft.VisualStudio.Services.TeamServicesAgentLinux
- /<agent directory>/_diag (The value for the directory per default is "agent")

Along with [Björn Sundling](https://bjompen.com/#/) we decided to team up to try and figure out how the [Azure DevOps Pipeline Agent Extension](https://learn.microsoft.com/en-us/azure/devops/pipelines/release/deployment-groups/howto-provision-deployment-group-agents?view=azure-devops) in Azure works, and the different ways of installing the Pipeline agent and configuring settings for it.

> The docs article explains how we can configure the Azure DevOps Extension to connect to a deployment group.
Deployment groups are not the same as Agent pools.
The article contains more information on the Extension itself as documentation is lacking here: [DevOps Agent Pools](https://learn.microsoft.com/en-us/azure/devops/pipelines/agents/agents?view=azure-devops&tabs=browser)
{: .prompt-info }

> Note that in the example ARM file a Personal Access Token (PAT) is required under the protected settings. You should never share your PAT with anyone and always keep it protected.
{: .prompt-info }

As part of our network design, it is decided that no web traffic may go directly to the internet destination, instead it will always go through a proxy.
If the traffic tries to reach it's destination without going through the proxy, the network security group (NSG) will stop it.
However the NSG will not interrupt web traffic within the virtual network.

>  I highely suggest that you use the Squid Proxy sever in Azure Marketplace to experiment or for a sandbox environment.
{: .prompt-info }

The first issue we will encounter is that the Azure DevOps Extension will fail it's installation.
This is because the Azure DevOps VM Extension cannot be downloaded, The extension is hosted on Microsoft generated storage accounts.
In my case the url was: https://umsaqts1kdw3dgdrdmzt.blob.core.windows.net/76d90c30-c607-43bc-49aa-02e322a01e7b/76d92c30-c607-43bc-49aa-32e322a01e7b_1.22.0.0.zip
If you want to see more details about the VM Extension download, you can find it at /var/log/azure/Microsoft.VisualStudio.Services.TeamServicesAgentLinux/CommandExecution.log
Example log of a successful download:
``` text
2022-11-04T08:55:06.150100Z INFO ExtHandler [Microsoft.VisualStudio.Services.TeamServicesAgentLinux-1.22.0.0] Target handler state: enabled [incarnation_1]
2022-11-04T08:55:06.150369Z INFO ExtHandler [Microsoft.VisualStudio.Services.TeamServicesAgentLinux-1.22.0.0] [Enable] current handler state is: notinstalled
2022-11-04T08:55:06.150627Z INFO ExtHandler [Microsoft.VisualStudio.Services.TeamServicesAgentLinux-1.22.0.0] Downloading extension package: https://umsaqts1kdw3dgdrdmzt.blob.core.windows.net/76d90c30-c607-43bc-49aa-02e322a01e7b/76d92c30-c607-43bc-49aa-32e322a01e7b_1.22.0.0.zip
2022-11-04T08:55:06.187235Z INFO ExtHandler [Microsoft.VisualStudio.Services.TeamServicesAgentLinux-1.22.0.0] Unzipping extension package: /var/lib/waagent/Microsoft.VisualStudio.Services.TeamServicesAgentLinux__1.22.0.0.zip
2022-11-04T08:55:06.191683Z INFO ExtHandler [Microsoft.VisualStudio.Services.TeamServicesAgentLinux-1.22.0.0] Initializing extension Microsoft.VisualStudio.Services.TeamServicesAgentLinux-1.22.0.0
2022-11-04T08:55:06.192513Z INFO ExtHandler [Microsoft.VisualStudio.Services.TeamServicesAgentLinux-1.22.0.0] Update settings file: 266.settings
2022-11-04T08:55:06.192717Z INFO ExtHandler [Microsoft.VisualStudio.Services.TeamServicesAgentLinux-1.22.0.0] Install extension [Handler.sh]
```
>  As you can see in the log above, this is where the settings file is generated.
{: .prompt-info }
Creates a settings file containing the ProtectedSettings and Settings property of the extension here:
/var/lib/waagent/Microsoft.VisualStudio.Services.TeamServicesAgentLinux-<versionnumber>/config/<uniquenumber>.settings

Once you have allowed the Azure DevOps VM extension to download itself, then the next problem will be that the Azure DevOps VM Extension itself is not proxy aware and fail when trying to download the agent zip and enable agent script.
Looking at the code for the Azure DevOps Extension, we can see on row 596 in the AzureRM.py that it will try to run the command: "Util.url_retrieve(downloadUrl, agentFile)".
The downloadUrl and agentFile is defined in the VM Extension part of your scale-set.
``` bicep
{
    "name": "Microsoft.Azure.DevOps.Pipelines.Agent",
    "properties": {
        "autoUpgradeMinorVersion": false,
        "publisher": "Microsoft.VisualStudio.Services",
        "type": "TeamServicesAgentLinux",
        "typeHandlerVersion": "1.22",
        "settings": {
            "isPipelinesAgent": true,
            "agentFolder": "/agent",
            "agentDownloadUrl": "https://vstsagentpackage.azureedge.net/agent/2.211.1/vsts-agent-linux-x64-2.211.1.tar.gz",
            "enableScriptDownloadUrl": "https://vstsagenttools.blob.core.windows.net/tools/ElasticPools/Linux/13/enableagent.sh"
        }
    }
}
```
The Util library is imported from the Utils/HandlerUtil.py module.
The url_retrieve function contains the following bit of code:
``` python
def url_retrieve(download_url, target):
  if ('ProxyUrl' in proxy_config):
    proxy_url = proxy_config['ProxyUrl']
    proxy_handler = urllib.request.ProxyHandler({'https': proxy_url})
    opener = urllib.request.build_opener(proxy_handler)
    urllib.request.install_opener(opener
  urllib.request.urlretrieve(download_url, target))
```
Which suggests that the function should be retreiving the proxy settings, if ProxyUrl is defined in "proxy_config".

Going back to the AzureRM.py script, we can see that the proxy_config is imported as 'from Utils.GlobalSettings import proxy_config'.
Reading the GlobalSettings.py file we can see that it contains the following:
``` python
proxy_config = {}
```
However, there is no function where this file gets populated on the fly depending on for example the machine variables http_proxy/https_proxy etc.
> Looking at the urllib documentation [urllib docs](https://docs.python.org/3/library/urllib.request.html) we can see that it supports a function of getting the proxy settings "request.getproxies()", but as part of the code it is not implemented.
{: .prompt-info }

As we cannot have the Extension to understand the use of proxy, we can we can edit the path for agentDownloadUrl and enableScriptDownloadUrl to be hosted on a internal Azure Storage Account.
This will allow the Azure DevOps Extension to download these files without a web proxy (as we are allowed to send web traffic within our virtual network without having the traffic dropped.)
``` bicep
{
    "name": "Microsoft.Azure.DevOps.Pipelines.Agent",
    "properties": {
        "autoUpgradeMinorVersion": false,
        "publisher": "Microsoft.VisualStudio.Services",
        "type": "TeamServicesAgentLinux",
        "typeHandlerVersion": "1.22",
        "settings": {
            "isPipelinesAgent": true,
            "agentFolder": "/agent",
            "agentDownloadUrl": "https://interaltestfeed.blob.core.windows.net/devops/vsts-agent-linux-x64-2.211.1.tar.gz",
            "enableScriptDownloadUrl": "https://interaltestfeed.blob.core.windows.net/devops/enableagent.sh"
        }
    }
}
```

Once you have successfully updated the extension settings, you can now read the log file @ /agent/_diag/Agent_<timestamp>-utc.log which contains the following rows that identifies that we have set the proxy correctly.
Correct setup.
``` text
[2022-11-04 08:23:39Z INFO AgentProcess] Arguments parsed
[2022-11-04 08:23:39Z INFO HostContext] Well known directory 'Bin': '/agent/bin'
[2022-11-04 08:23:39Z INFO HostContext] Well known directory 'Root': '/agent'
[2022-11-04 08:23:39Z INFO HostContext] Well known config file 'Proxy': '/agent/.proxy'
[2022-11-04 08:23:39Z INFO VstsAgentWebProxy] Config proxy at: http://10.2.0.7:3128.
[2022-11-04 08:23:39Z INFO HostContext] Well known directory 'Bin': '/agent/bin'
[2022-11-04 08:23:39Z INFO HostContext] Well known directory 'Root': '/agent'
[2022-11-04 08:23:39Z INFO HostContext] Well known config file 'ProxyCredentials': '/agent/.proxycredentials'
[2022-11-04 08:23:39Z INFO VstsAgentWebProxy] Config proxy use DefaultNetworkCredentials.
```

If the string is not a correct formated string (https/http://<proxyaddress>:<port>).
``` text
[2022-11-04 07:48:33Z INFO AgentProcess] Arguments parsed
[2022-11-04 07:48:33Z INFO HostContext] Well known directory 'Bin': '/agent/bin'
[2022-11-04 07:48:33Z INFO HostContext] Well known directory 'Root': '/agent'
[2022-11-04 07:48:33Z INFO HostContext] Well known config file 'Proxy': '/agent/.proxy'
[2022-11-04 07:48:33Z ERR  VstsAgentWebProxy] The proxy url is not a well formed absolute uri string: 10.2.0.7:3128.
[2022-11-04 07:48:33Z INFO VstsAgentWebProxy] No proxy setting found.
```

Now you Azure DevOps agent can identify and report back to Azure DevOps correctly!
However as the Azure DevOps agent also needs to install tools that might not exist on the machine, we will have to set the apt proxy as well.
There's different ways of setting the apt proxy, however to keep it simple I have chosen to create the apt.conf file at /etc/apt with the content:
``` text
Acquire::http::Proxy "http://10.2.0.7:3128";
```



> The protected settings part of the settings file is encrypted, the VMSS instance has a computer certificate installed to decrypt the value.
During the extension installation the protected settings on disk will be wiped after read.
This can be intercepted in various ways, if you are interested to read the settings file.
Part of the protected settings contains a JWT for the agent to authenticate to the Azure DevOps instance to call home.
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
