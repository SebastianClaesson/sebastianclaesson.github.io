---
title: Azure DevOps Pipeline Agent Extension (Ubuntu) - Unauthenticated/Authenticated Proxy.
date: 2022-11-07 17:55:00
categories: [Azure, AzureDevOps]
tags: [powershell,azure,devops,extension,virtual machine,vmss,proxy,ubuntu]     # TAG names should always be lowercase
---

Are you looking to run your Azure DevOps agent behind an unauthenticated/authenticated web proxy for traffic destined to the internet?
Then hopefully this post will help you straighten out those question marks that might come up during the process.

We'll start first with a summary of how the installation and deployment of the Azure DevOps VM Extension works, this will help us get an insight of what steps in the process where issues might occur.
1. VM/VMSS has the Azure DevOps Extension deployed to it, using the portal, cli or infrastructure-as-code.
2. The VM/VMSS will download the extension in a compressed format (zip) from a public Azure Storage Account.
3. The Extension will run the "Handler.sh -enable" command and run either AzureRM.py or AzureRM_Python2.py (depending on what Python version is available) to install the DevOps Agent.
4. AzureRM.py (or AzureRM_Python2.py) will read the settings file (containing the Public and Protected Settings), decrypt the protected settings with the computer certificate available and remove it from the settings file.
5. AzureRM.py will download the Azure DevOps agent zip file and EnableAgent script specified in the Public settings.
6. The InstallDependecies.sh script will use APT to install missing dependencies.
7. The Azure DevOps agent installation will start and configure itself according to the scenario specified.

The log locations for the Azure DevOps VM Extension are:
- /var/log/azure/Microsoft.VisualStudio.Services.TeamServicesAgentLinux
- /agent directory/_diag (The value for the directory per default is "agent")

> Read more about the communication and setup of [Azure DevOps Agent](https://learn.microsoft.com/en-us/azure/devops/pipelines/agents/agents?view=azure-devops&tabs=browser)
{: .prompt-info }

As part of our network design, it is decided that no web traffic may go directly to the internet destination, instead it will always go through a proxy.

If the traffic tries to reach it's destination without going through the proxy, the network security group (NSG) will stop it.
However the NSG will not interrupt web traffic within the virtual network.

>  I highely suggest that you use the [Squid Proxy Server](https://azuremarketplace.microsoft.com/en-us/marketplace/apps/cloud-infrastructure-services.squid-ubuntu-2004?tab=Overview) in Azure Marketplace to experiment with, Note that the product has an hourly cost.
{: .prompt-info }

The first thing we will have to do is to create the Bicep template.

{::options parse_block_html="true" /}

<details><summary markdown="span">VMSS Bicep Template Example</summary>
``` plaintext
var location = resourceGroup().location
var AzureDevOpsPATToken = 'AzureDevOpsPATToken'
var subnetId = '/subscriptions/81bee834-3e8e-4f5d-bb31-3316a05e5583/resourceGroups/demo-rg/providers/Microsoft.Network/virtualNetworks/demo-vnet/subnets/demo-snet'

resource vmss 'Microsoft.Compute/virtualMachineScaleSets@2022-03-01' = {
  name: 'demo-vmss'
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  sku: {
    capacity: 1
    name: 'Standard_B2ms'
  }
  properties: {
    overprovision: false
    upgradePolicy: {
      mode: 'Manual'
    }
    singlePlacementGroup: false
    virtualMachineProfile: {
      storageProfile: {
        osDisk: {
          createOption: 'FromImage'
        }
        imageReference: {
          publisher: 'canonical'
          offer: '0001-com-ubuntu-server-focal'
          sku: '20_04-lts-gen2'
          version: 'latest'
        }
      }
      osProfile: {
        adminPassword: 'DemoTest123'
        adminUsername: 'demouser'
        computerNamePrefix: 'demo'
      }
      networkProfile: {
        networkInterfaceConfigurations: [
          {
            name: 'demo-vmss-nic'
            properties: {
              primary: true
              enableAcceleratedNetworking: false
              ipConfigurations: [
                {
                  name: 'demo-vmss-nic-ipc'
                  properties: {
                    primary: true
                    subnet: {
                      id: subnetId
                    }
                  }
                }
              ]
            }
          }
        ]
      }
      extensionProfile: {
        extensions:[
          {
            name: 'Microsoft.Azure.DevOps.Pipelines.Agent'
            properties: {
                autoUpgradeMinorVersion: false
                publisher: 'Microsoft.VisualStudio.Services'
                type: 'TeamServicesAgentLinux'
                typeHandlerVersion: '1.23'
                settings: {
                    isPipelinesAgent: true
                    agentFolder: '/agent'
                    AzureDevOpsOrganizationUrl: 'https://dev.azure.com/sebcla'
                    TeamProject: 'Demo'
                    enableScriptParameters: 'https://dev.azure.com/sebcla AgentPoolName ${AzureDevOpsPATToken}'
                    agentDownloadUrl: 'https://vstsagentpackage.azureedge.net/agent/2.211.1/vsts-agent-linux-x64-2.211.1.tar.gz'
                    enableScriptDownloadUrl: 'https://vstsagenttools.blob.core.windows.net/tools/ElasticPools/Linux/14/enableagent.sh'
                }
                protectedSettings: {
                  PATToken: AzureDevOpsPATToken
                }
            }
        }
        ]
      }
    }
  }
}
```
</details>
<br/>
> Currently rouge do not support Bicep syntax highlighting. 
If you would like to see Bicep hightlighting, then please up-vote [Rouge Bicep Hightlighting](https://github.com/rouge-ruby/rouge/issues/1887) at GitHub.
{: .prompt-info }

> Note that in the example ARM file a Personal Access Token (PAT) is used under the protected settings. You should never share your PAT with anyone and always keep it protected, therefor it is not a good practice to use the PAT in clear text of your deployment. Please make sure you only issue short-lived tokens if you are to use them in clear text or use a keyvault reference.
Read more about that here: [Microsoft.Compute/virtualMachines/extensions](https://learn.microsoft.com/en-us/azure/templates/microsoft.compute/virtualmachines/extensions?pivots=deployment-language-bicep#keyvaultsecretreference)
{: .prompt-info }

The first issue we will encounter is that the Azure DevOps Extension will fail it's installation.

This is because the Azure DevOps VM Extension cannot be downloaded, The extension is hosted on Microsoft generated storage accounts.

In my case the url was: https://umsaqts1kdw3dgdrdmzt.blob.core.windows.net/76d90c30-c607-43bc-49aa-02e322a01e7b/76d92c30-c607-43bc-49aa-32e322a01e7b_1.22.0.0.zip

If you want to see more details about the VM Extension download, you can find it at /var/log/azure/Microsoft.VisualStudio.Services.TeamServicesAgentLinux/CommandExecution.log

*Example log of a successful download:*
``` text
2022-11-04T08:55:06.150100Z INFO ExtHandler [Microsoft.VisualStudio.Services.TeamServicesAgentLinux-1.22.0.0] Target handler state: enabled [incarnation_1]
2022-11-04T08:55:06.150369Z INFO ExtHandler [Microsoft.VisualStudio.Services.TeamServicesAgentLinux-1.22.0.0] [Enable] current handler state is: notinstalled
2022-11-04T08:55:06.150627Z INFO ExtHandler [Microsoft.VisualStudio.Services.TeamServicesAgentLinux-1.22.0.0] Downloading extension package: https://umsaqts1kdw3dgdrdmzt.blob.core.windows.net/76d90c30-c607-43bc-49aa-02e322a01e7b/76d92c30-c607-43bc-49aa-32e322a01e7b_1.22.0.0.zip
2022-11-04T08:55:06.187235Z INFO ExtHandler [Microsoft.VisualStudio.Services.TeamServicesAgentLinux-1.22.0.0] Unzipping extension package: /var/lib/waagent/Microsoft.VisualStudio.Services.TeamServicesAgentLinux__1.22.0.0.zip
2022-11-04T08:55:06.191683Z INFO ExtHandler [Microsoft.VisualStudio.Services.TeamServicesAgentLinux-1.22.0.0] Initializing extension Microsoft.VisualStudio.Services.TeamServicesAgentLinux-1.22.0.0
2022-11-04T08:55:06.192513Z INFO ExtHandler [Microsoft.VisualStudio.Services.TeamServicesAgentLinux-1.22.0.0] Update settings file: 266.settings
2022-11-04T08:55:06.192717Z INFO ExtHandler [Microsoft.VisualStudio.Services.TeamServicesAgentLinux-1.22.0.0] Install extension [Handler.sh]
```
> As you can see in the log above, this is where the settings file is generated.
The path of the settings file: /var/lib/waagent/Microsoft.VisualStudio.Services.TeamServicesAgentLinux-<versionnumber>/config/<uniquenumber>.settings
The settings files contains the ProtectedSettings and Settings attribute of the extension.
{: .prompt-info }

Once you have allowed the Azure DevOps VM extension to download itself, then the next problem will be that the Azure DevOps VM Extension itself is not proxy aware and fail when trying to download the agent zip and enable agent script.

Looking at the code for the Azure DevOps Extension, we can see on row 596 in the AzureRM.py that it will try to run the command: "Util.url_retrieve(downloadUrl, agentFile)".

The downloadUrl and agentFile is defined in the VM Extension part of your scale-set.
``` plaintext
{
    name: 'Microsoft.Azure.DevOps.Pipelines.Agent'
    properties: {
        autoUpgradeMinorVersion: false
        publisher: 'Microsoft.VisualStudio.Services'
        type: 'TeamServicesAgentLinux'
        typeHandlerVersion: '1.22'
        settings: {
            isPipelinesAgent: true
            agentFolder: '/agent'
            AzureDevOpsOrganizationUrl: 'https://dev.azure.com/sebcla'
            TeamProject: 'Demo'
            enableScriptParameters: 'https://dev.azure.com/sebcla AgentPoolName ${AzureDevOpsPATToken}'
            agentDownloadUrl: 'https://vstsagentpackage.azureedge.net/agent/2.211.1/vsts-agent-linux-x64-2.211.1.tar.gz'
            enableScriptDownloadUrl: 'https://vstsagenttools.blob.core.windows.net/tools/ElasticPools/Linux/14/enableagent.sh'
        }
        protectedSettings: {
          PATToken: AzureDevOpsPATToken
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

As we cannot make the Extension understand that it should use a proxy, we can edit the path for agentDownloadUrl and enableScriptDownloadUrl to be hosted on a Azure Storage Account with a private endpoint in the same virtual network as the VMSS.

This will allow the Azure DevOps Extension to download these files without a web proxy.
As we are allowed to send web traffic within our virtual network without having the traffic dropped.
``` plaintext
{
    name: 'Microsoft.Azure.DevOps.Pipelines.Agent'
    properties: {
        autoUpgradeMinorVersion: false
        publisher: 'Microsoft.VisualStudio.Services'
        type: 'TeamServicesAgentLinux'
        typeHandlerVersion: '1.22'
        settings: {
            isPipelinesAgent: true
            agentFolder: '/agent'
            AzureDevOpsOrganizationUrl: 'https://dev.azure.com/sebcla'
            TeamProject: 'Demo'
            enableScriptParameters: 'https://dev.azure.com/sebcla AgentPoolName ${AzureDevOpsPATToken}'
            agentDownloadUrl: 'https://internaltestfeed.blob.core.windows.net/devops/vsts-agent-linux-x64-2.211.1.tar.gz'
            enableScriptDownloadUrl: 'https://internaltestfeed.blob.core.windows.net/devops/enableagent.sh'
        }
        protectedSettings: {
          PATToken: AzureDevOpsPATToken
        }
    }
}
```
Once you have successfully updated the extension settings, you can now read the log file @ /agent/_diag/Agent_timestamp-utc.log which contains the following rows that identifies that we have set the proxy correctly.

*Correct setup*
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
*If the string is not a correct formated string (https/http://proxyaddress:port)*
``` text
[2022-11-04 07:48:33Z INFO AgentProcess] Arguments parsed
[2022-11-04 07:48:33Z INFO HostContext] Well known directory 'Bin': '/agent/bin'
[2022-11-04 07:48:33Z INFO HostContext] Well known directory 'Root': '/agent'
[2022-11-04 07:48:33Z INFO HostContext] Well known config file 'Proxy': '/agent/.proxy'
[2022-11-04 07:48:33Z ERR  VstsAgentWebProxy] The proxy url is not a well formed absolute uri string: 10.2.0.7:3128.
[2022-11-04 07:48:33Z INFO VstsAgentWebProxy] No proxy setting found.
```
Now you Azure DevOps agent can identify and report back to Azure DevOps correctly!

Maybe now you have started to wonder - I have issued an Azure DevOps token, where and how is it stored?

Well, to make it simple, the token is used to issue a JWT towards Azure DevOps.

The JWT issued is only valid for a short time and can be used to report back as a healthy agent to Azure DevOps.

The settings file will be inserted into the VM/instance you are running and available on disk.
If you want to decrypt it manually, it is possible by using the Python module "HandlerUtil.py" as it contains a function to decode the settings using the computer certificate.
The code for it:
``` python
_parse_config(self, ctxt, operation):
        config = None
        try:
            config=json.loads(ctxt)
        except:
            self.error('JSON exception decoding ' + ctxt)

        if config == None:
            self.error("JSON error processing settings file:" + ctxt)
        else:
            handlerSettings = config['runtimeSettings'][0]['handlerSettings']
            if 'protectedSettings' in handlerSettings and \
                    "protectedSettingsCertThumbprint" in handlerSettings and \
                    handlerSettings['protectedSettings'] is not None and \
                    handlerSettings['protectedSettings'] != '' and \
                    handlerSettings["protectedSettingsCertThumbprint"] is not None:
                protectedSettings = handlerSettings['protectedSettings']
                thumb=handlerSettings['protectedSettingsCertThumbprint']
                cert=waagent.LibDir+'/'+thumb+'.crt'
                pkey=waagent.LibDir+'/'+thumb+'.prv'
                waagent.SetFileContents('/tmp/kk', protectedSettings)
                cleartxt=None
                cleartxt=waagent.RunGetOutput("base64 -d /tmp/kk | openssl smime  -inform DER -decrypt -recip " +  cert + "  -inkey " + pkey )[1]
                os.remove("/tmp/kk")
                if cleartxt == None:
                    self.error("OpenSSh decode error using  thumbprint " + thumb )
                    self.do_exit(1,operation,'error','1', operation + ' Failed')
                jctxt=''
                try:
                    jctxt=json.loads(cleartxt)
                except:
                    self.error('JSON exception decoding ' + cleartxt)
                handlerSettings['protectedSettings']=jctxt
                self.log('Config decoded correctly.')
        return config
```
*Example of settings file on disk.*
``` json
{
  "runtimeSettings": [
    {
      "handlerSettings": {
        "protectedSettingsCertThumbprint": "C995E47CEFBD87EBA02B01E1BBFBA6D1A6E83352",
        "protectedSettings": "MIIF3AYJKoZIhvcNAQcDoIIFzTCCBckCAQAxggFpMIIBZQIBADBNMDkxNzA1BgoJkiaJk/IsZAEZFidXaW5kb3dzIEF6dXJlIENSUCBDZXJ0aWZpY2F0ZSBHZW5lcmF0b3ICEE5Dxku1ulysRjLkep1nhIcwDQYJKoZIhvcNAQEBBQAEggEAf1+0EYEt/c4yDLdQTQemZMyWF8pUrjJuM222sHXiqQvzpzi0L+ezgRFQw+/3cr0QXUytuEOLsrWZcEziOONhZhaCaSD+58JRwU+Z006nJxg+rM06EP3ff12J36PfYR5/+YDYgs66uG6A+S3Y2ZoMczbCpRItH0iCeyFOnPSRGpWISqFA9tpw+HpqHWlY5WM8ugngsQSRPeUFtjb62e9z+LWvJq6z0nh7oIMUMLB/jCEIfUi7eH3egMLHZHaX+QD+O0B7gXD+L5d5a4+AXkkZle0eVuzdUJGgcwPGf56xGMYikHx0Yfuc9QtV+bCzRAcahalKE1WflyEmZU6aZHOrPjCCBFUGCSqGSIb3DQEHATAUBggqhkiG9w0DBwQIbICCIhCAggQw0v+55ijfEDXiy7Tl+4JsG4pYVW1G2iI9iAXqAL4LcVFEvWE3+Q1UY59S34tbJAxxMbuoZX8ij97gE0+icQZL/sq6M3x0QXK+XGrIkG5nW/mGta7OGV/DKAaZt5jlKzgWq2klCrVSc5Xm3nuh+5mU3EltcAvc4q7wRsx4LWXC8AL4PIcD1SnjUrn7M87QrlMxG6GL3iSJEA8tUXDVgdoQKgUiatnQXOpTIcIiOIdFKrYJxbePUUSN5qyAf8rXZ4Ta9kp3xR0AdXtPQ0SHAbd+LaVztXzkbG8l7PnV4KJNXZCo4Vob7dN4crE7/abZZDV5FpWaWcZIeBIdcqAItHvFtQ8Rq9xwb/urI6vdbUZeVaI61+JLqp3ZLhIfzeejOtlH3HxQk4xofg+br5QEx2k+k47HAZE5xh5xRQwH6G5sSsYfDvFvFBmdaEJByfvh2Tv0a4JqYKoANjCVBvu5zAl88MukkIloxc1rdGtIyvBDC0uWYf2gFAE92g2a+B8EaYDFxOLQV8ZC1k1ZCtLQiYe/NdtbsUJnGPesdJ1sBLdmidclPO6gyB/HAXoJgdmx7ppFylO0A3RJnGyc85oORhc/qPkicT1a61aZlg+MrCwolQ2ImBZrzMCMWK/smgNEGJYa8ksPjhY3Mb1QHDFOc8uzQCFDhQI+F6psNbuvYrPdm4Jjcb5vIdlojEBMuWqbFwHX/29tPU/5tMZ2H+tABzI9b1CbdY5kbmTUQfX3+tQladdNF8hvS1WLgYuvOMpdn9sYiwOvmsKf8oolrzoQ4Occ2eAMhQDWAWyWr1M2E0KB6dEMQApwAoVVdPWicf+1WIMzyY6MoRW1FZbMtkqJDiZYJo0zmSmnpK1tCZWKh+1m83o5b5U34doFa7TZbRCjdDL1CYTEBQWGJdFHFh0ktqlg7pqihy6cpjJOhnEEaEEX74cTVx9nFCmAQPW/4dYeplq5gbT188/+kd5dKTcckp4uHLvH4+m2f09qp5Vv1vvYmenSn/B5uI9l4fr21kVuSaTyF3bEt9ajHKXho8sgHP2lRmla0pyRVPU/eEClCsXpJxKsYehQ76NA8jG51GvjUm5T1ZKPRxk94p98pWTjeAZ+6jJ0t0nG20tFST1YauQlj2Px9t1X3KQRwyO3rzlCKoMAVYtAykUsXesgIKt42FXqzbxkeVRIARkSHA2g2ELwYFsrZEZUa6zG3g5829vknWax6dDDe78CyjWE0EmdcZqlJMpEcEeUl/ObsgNnubPS8RLRO9ZSbvRAhTTUY7vhuH6O9zW9E+Awmg+nWHXKn6o+HGc/2S/jNdYaUPzZNwoHzYafoYQAuMonRs+PIpyNOSlw1ixEwyjqDRop0rGCHb0gj07yNp3XykXx0lIlEaNa1oPDQNey0NZo4pL6QJZ0/pA==",
        "publicSettings": {
          "isPipelinesAgent": true,
          "agentFolder": "/agent",
          "agentDownloadUrl": "https://internaltestfeed.blob.core.windows.net/devops/vsts-agent-linux-x64-2.211.1.tar.gz",
          "enableScriptDownloadUrl": "https://internaltestfeed.blob.core.windows.net/devops/enableagent.sh"
        }
      }
    }
  ]
}
```
> The protected settings part of the settings file is encrypted, the VMSS instance has a computer certificate installed to decrypt the value.
During the extension installation the protected settings on disk will be wiped after read.
This can be intercepted in various ways, if you are interested to read the settings file.
Part of the protected settings contains a JWT for the agent to authenticate to the Azure DevOps instance to call home.
{: .prompt-info }

However as the Azure DevOps agent also needs to install tools that might not exist on the machine, we will have to set the APT proxy as well.

There's different ways of setting the apt proxy, however to keep it simple I have chosen to create the apt.conf file at /etc/apt with the content:
``` text
Acquire::http::Proxy "http://10.2.0.7:3128";
```
This can either be done by the CustomScript extension or as part of a golden image capturing.
Once all of these configurations have been set in place, then you will successfully be able to use your proxy and reach Azure DevOps/APT.
Meaning the agent can now download the files needed, call home to Azure DevOps and download the dependencies needed to install successfully.

I hope this helps to cast some clarity on how the Azure DevOps agent extension works and how it can be used behind a proxy.
Thank you for reading!