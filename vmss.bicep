var location = 'West europe'
var userId = '90d50f94-10e8-494d-bece-ea990d773b47'
var devopsAccountName = 'https://dev.azure.com/advaniase'
var devopsTeamProject = 'TeamAutomation'
var agentName = 'demo-'
var devopsDeploymentGroup = '496'

resource virtualNetwork 'Microsoft.Network/virtualNetworks@2019-11-01' = {
  name: 'demo-vnet'
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        '172.16.20.0/22'
      ]
    }
    subnets: [
      {
        name: 'demo-snet-1'
        properties: {
          addressPrefix: '172.16.20.0/24'
        }
      }
    ]
  }
}

resource keyVault 'Microsoft.KeyVault/vaults@2019-09-01' = {
  name: 'demo-${uniqueString(subscription().subscriptionId)}-kv'
  location: location
  properties: {
    enabledForDeployment: true
    enabledForTemplateDeployment: true
    enabledForDiskEncryption: true
    tenantId: subscription().tenantId
    enableRbacAuthorization: true
    sku: {
      name: 'standard'
      family: 'A'
    }
  }
}

resource keyVaultSecret 'Microsoft.KeyVault/vaults/secrets@2019-09-01' = {
  name: 'pat'
  parent: keyVault
  properties: {
    value: '{"PATToken": "6rtplgj2k7ywvbbwpwjqwd2uif7kkisovvc6b6wxhe3oawxtvqda"}'
  }
}

resource rbac 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: keyVault
  name: guid('demo-rbac',userId)
  properties: {
    roleDefinitionId: 'b86a8fe4-44ce-4948-aee5-eccb2c155cd7'
    principalId: userId
    principalType: 'User'
  }
}

resource vmss 'Microsoft.Compute/virtualMachineScaleSets@2022-03-01' = {
  name: 'demo-vmss'
  location: location
  properties: {
    overprovision: false
    upgradePolicy: {
      mode: 'Manual'
    }
    singlePlacementGroup: false
    virtualMachineProfile: {
      osProfile: {
        adminUsername: 'demosuperadminuser'
        adminPassword: 'demosuperadminpassword123#!'
        computerNamePrefix: 'demo-'
        windowsConfiguration: {
          provisionVMAgent: true
          enableAutomaticUpdates: true
        }
        allowExtensionOperations: true
      }
      storageProfile: {
        imageReference: {
          publisher: 'MicrosoftWindowsServer'
          offer: 'WindowsServer'
          sku: '2022-datacenter-azure-edition'
          version: 'latest'
        }
        osDisk: {
          osType: 'Windows'
          createOption: 'FromImage'
          caching: 'ReadWrite'
          diskSizeGB: 127
        }
      }
      networkProfile: {
        networkInterfaceConfigurations: [
          {
            name: 'demo-nic'
            properties: {
              ipConfigurations: [
               {
                name: 'demo-ip-config'
                properties: {
                  subnet: {
                   id: virtualNetwork.properties.subnets[0].id
                  }
                }
               } 
              ]
              primary: true
              enableAcceleratedNetworking: true
            }
          }
        ]
      }
      extensionProfile: {
        extensions: [
          {
            name: 'config'
            properties: {
              publisher: 'Microsoft.Compute'
              type: 'CustomScriptExtension'
              typeHandlerVersion: '1.10'
              autoUpgradeMinorVersion: false
              settings: {
                timestamp: 123456789
              }
              protectedSettings: {
                commandToExecute: 'mkdir C:\\Agent & mkdir C:\\Packages\\Plugins\\Microsoft.VisualStudio.Services.TeamServicesAgent\\1.29.0.0 & echo https://127.0.0.0:8888 > C:\\Packages\\Plugins\\Microsoft.VisualStudio.Services.TeamServicesAgent\\1.29.0.0\\.proxy & echo https://127.0.0.0:8888 > "C:\\Agent\\.proxy" & SETX VSTS_AGENT_INPUT_WORK "C:\\Agent" /m & SETX VSTS_AGENT_INPUT_URL "${devopsAccountName}" /m & SETX VSTS_AGENT_INPUT_POOL "${devopsDeploymentGroup}" /m & SETX VSTS_AGENT_INPUT_POOL "${devopsDeploymentGroup}" /m' // 'SETX http_proxy "http://127.0.0.1:8888 --unattended --auth pat --token 6rtplgj2k7ywvbbwpwjqwd2uif7kkisovvc6b6wxhe3oawxtvqda --pool 496 --replace --runAsService" /m'
              } // '[System.Environment]::SetEnvironmentVariable("http_proxy", "http://127.0.0.1:8888 --unattended --auth pat --token 6rtplgj2k7ywvbbwpwjqwd2uif7kkisovvc6b6wxhe3oawxtvqda --pool 496 --agent --replace --runAsService", [System.EnvironmentVariableTarget]::Machine)'
            }
          }
          {
            name: 'Microsoft.Azure.DevOps.Pipelines.Agent'
            properties: {
              autoUpgradeMinorVersion: false
              publisher: 'Microsoft.VisualStudio.Services'
              type: 'TeamServicesAgent'
              typeHandlerVersion: '1.29'
              settings: {
                isPipelinesAgent: true
                agentFolder: 'C:\\agent'
                AzureDevOpsOrganizationUrl: devopsAccountName
                TeamProject: devopsTeamProject
                DeploymentGroup: devopsDeploymentGroup
                // AgentName: agentName
                agentDownloadUrl: 'https://vstsagentpackage.azureedge.net/agent/2.211.0/vsts-agent-win-x64-2.211.0.zip'
                enableScriptDownloadUrl: 'https://vstsagenttools.blob.core.windows.net/tools/ElasticPools/Windows/15/enableagent.ps1'
                // enableScriptParameters: '""'// '"-url "${devopsAccountName} --proxyurl http://127.0.0.1:8888" -pool "${devopsDeploymentGroup}" -token "6rtplgj2k7ywvbbwpwjqwd2uif7kkisovvc6b6wxhe3oawxtvqda""' // --unattended --auth pat --token 6rtplgj2k7ywvbbwpwjqwd2uif7kkisovvc6b6wxhe3oawxtvqda --pool ${devopsDeploymentGroup} --agent ${agentName} --replace --runAsService"' // '${devopsAccountName} ${devopsDeploymentGroup}' // --proxyurl http://127.0.0.1:8888"'
              }
              protectedSettings: {
                PATToken: '6rtplgj2k7ywvbbwpwjqwd2uif7kkisovvc6b6wxhe3oawxtvqda'
              }
              // protectedSettingsFromKeyVault: {
              //   secretUrl: keyVaultSecret.properties.secretUriWithVersion
              //   sourceVault: {
              //     id: keyVault.id
              //   }
              // }
            }
          }
        ]
      }
    }
    scaleInPolicy: {
      rules: [
        'Default'
      ]
    }
  }
  sku: {
    name: 'Standard_D4s_v5'
    tier: 'Standard'
    capacity: 1
  }
}
