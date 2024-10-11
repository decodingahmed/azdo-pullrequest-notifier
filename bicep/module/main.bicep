@description('The prefix to add to all resource names.')
param project_prefix string

@description('The prefix of the email subject.')
param email_subject_prefix string = 'PR Bulletin'

@description('The URL of the Azure DevOps project.')
param project_url string

@description('The Azure DevOps Personal Access Token to request the list of Pull Requests.')
@secure()
param azdo_access_token string

@description('The URL of the Teams Channel Webhook to post the PR Notification to.')
param teams_channel_webhook_url string

@description('The deployment region for resources.')
param region string = 'uksouth'

@description('The email addresses to send the PR Notification to.')
param email_addresses array

//
// Communications Services
//

resource email_communications_service 'Microsoft.Communication/emailServices@2023-04-01' = {
  location: 'global'
  name: '${project_prefix}-prnotifier-ecs'
  properties: {
    dataLocation: 'UK'
  }
}

resource email_services_managed_domain 'Microsoft.Communication/emailServices/domains@2023-04-01' = {
  parent: email_communications_service
  location: 'global'
  name: 'AzureManagedDomain'
  properties: {
    domainManagement: 'AzureManaged'
    userEngagementTracking: 'Disabled'
  }
}

resource email_services_sender 'microsoft.communication/emailservices/domains/senderusernames@2023-04-01' = {
  parent: email_services_managed_domain
  name: 'donotreply'
  properties: {
    displayName: 'DoNotReply'
    username: 'DoNotReply'
  }
}

resource communications_service 'Microsoft.Communication/CommunicationServices@2023-04-01' = {
  location: 'global'
  name: '${project_prefix}-prnotifier-cs'
  properties: {
    dataLocation: 'UK'
    linkedDomains: [
      email_services_managed_domain.id
    ]
  }
}

//
// Key Vault
//

resource keyvault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  location: region
  name: '${project_prefix}-prnotifier-kv'
  properties: {
    accessPolicies: []
    enableRbacAuthorization: false
    enableSoftDelete: true
    enabledForDeployment: false
    enabledForDiskEncryption: false
    enabledForTemplateDeployment: false
    provisioningState: 'Succeeded'
    publicNetworkAccess: 'Enabled'
    sku: {
      family: 'A'
      name: 'standard'
    }
    softDeleteRetentionInDays: 90
    tenantId: tenant().tenantId
  }
}

resource keyVaultAccessPolicy 'Microsoft.KeyVault/vaults/accessPolicies@2023-07-01' = {
  parent: keyvault
  name: 'add'
  properties: {
    accessPolicies: [
      {
        objectId: logic_app.identity.principalId
        permissions: {
          certificates: []
          keys: []
          secrets: [
            'list'
            'get'
          ]
        }
        tenantId: subscription().tenantId
      }
    ]
  }
}

resource azdoAccessTokenSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyvault
  name: 'azdoAccessToken'
  properties: {
    value: azdo_access_token
    contentType: 'text/plain'
    attributes: {
      enabled: true
    }
  }
}

//
// API Connections
//

var communications_service_connection_name = '${project_prefix}-prnotifier-ecs-connection'
resource communications_service_connection 'Microsoft.Web/connections@2018-07-01-preview' = {
  location: region
  name: communications_service_connection_name
  kind: 'V1'
  properties: {
    api: {
      brandColor: '#3C1D6E'
      description: 'Connector to send Email using the domains linked to the Azure Communication Services in your subscription.'
      displayName: 'Azure Communication Services Email'
      // id: '/subscriptions/${subscriptionId}/providers/Microsoft.Web/locations/${region}/managedApis/${communications_service_connection_name}'
      id: subscriptionResourceId('Microsoft.Web/locations/managedApis', region, 'acsemail')
    }
    displayName: 'ecs'
    parameterValues: {
      api_key: communications_service.listKeys().primaryConnectionString
    }
    testLinks: []
  }
}

var keyvault_connection_name = '${project_prefix}-prnotifier-kv-connection'
resource keyvault_connection 'Microsoft.Web/connections@2018-07-01-preview' = {
  location: region
  name: keyvault_connection_name
  kind: 'V1'
  properties: {
    api: {
      brandColor: '#0079d6'
      description: 'Azure Key Vault is a service to securely store and access secrets.'
      displayName: 'Azure Key Vault'
      iconUri: 'https://connectoricons-prod.azureedge.net/releases/v1.0.1656/1.0.1656.3432/keyvault/icon.png'
      // id: '/subscriptions/${subscription().subscriptionId}/providers/Microsoft.Web/locations/${region}/managedApis/keyvault'
      id: subscriptionResourceId('Microsoft.Web/locations/managedApis', region, 'keyvault')
    }
    displayName: 'keyvault'
    testLinks: []
    parameterValueSet: {
      name: 'oauthMI'
      values: {
        vaultName: {
          value: keyvault.name
        }
        token: {}
      }
    }
  }
}

//
// Logic App
//

resource logic_app 'Microsoft.Logic/workflows@2019-05-01' = {
  identity: {
    type: 'SystemAssigned'
  }
  location: region
  name: '${project_prefix}-prnotifier-la'
  properties: {
    definition: {
      '$schema': 'https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#'
      actions: {
        Condition: {
          actions: {
            Add_WIP_tip: {
              inputs: {
                name: 'email_body_html'
                value: '<br>💡 See your PR above but it isn\'t ready yet? Prefix "WIP" to the title of your PR to filter it out.'
              }
              runAfter: {
                End_table: [
                  'Succeeded'
                ]
              }
              type: 'AppendToStringVariable'
            }
            End_table: {
              inputs: {
                name: 'email_body_html'
                value: '</table>'
              }
              runAfter: {
                Loop_through_PRs: [
                  'Succeeded'
                ]
              }
              type: 'AppendToStringVariable'
            }
            Intro: {
              inputs: {
                name: 'email_body_html'
                value: '<p>Here are some PRs that need your attention.</p><p>Number of PRs: @{length(body(\'Filter_out_Draft_and_WIP_PRs\'))}</p>'
              }
              runAfter: {}
              type: 'AppendToStringVariable'
            }
            Loop_through_PRs: {
              actions: {
                Append_PR_Entry: {
                  inputs: {
                    name: 'email_body_html'
                    value: '<tr><td><a href="@{item()[\'url\']}">PR @{item()[\'pullRequestId\']}: @{item()[\'title\']}</a></td> <td>@{item()[\'repositoryName\']}</td> <td>@{item()[\'author\']}</td></tr>'
                  }
                  runAfter: {}
                  type: 'AppendToStringVariable'
                }
              }
              foreach: '@body(\'Filter_out_Draft_and_WIP_PRs\')'
              runAfter: {
                Start_table: [
                  'Succeeded'
                ]
              }
              type: 'Foreach'
            }
            Start_table: {
              inputs: {
                name: 'email_body_html'
                value: '<table><th><tr><td>Pull Request</td><td>Repository</td><td>Author</td></tr></th>'
              }
              runAfter: {
                Intro: [
                  'Succeeded'
                ]
              }
              type: 'AppendToStringVariable'
            }
          }
          else: {
            actions: {
              Terminate: {
                type: 'Terminate'
                inputs: {
                  runStatus: 'Succeeded'
                }
              }
            }
          }
          expression: {
            and: [
              {
                greater: [
                  '@length(body(\'Filter_out_Draft_and_WIP_PRs\'))'
                  0
                ]
              }
            ]
          }
          runAfter: {
            Filter_out_Draft_and_WIP_PRs: [
              'Succeeded'
            ]
          }
          type: 'If'
        }
        Filter_out_Draft_and_WIP_PRs: {
          inputs: {
            from: '@body(\'Map_PR_Entries\')'
            where: '@equals(or(item().isDraft, item().isWorkInProgress), false)'
          }
          runAfter: {
            Map_PR_Entries: [
              'Succeeded'
            ]
          }
          type: 'Query'
        }
        Get_All_Open_PRs: {
          description: 'This gets all the open PRs (active and draft) in a project. See AzDO REST API docs: https://learn.microsoft.com/en-us/rest/api/azure/devops/git/pull-requests/get-pull-requests-by-project?view=azure-devops-rest-6.0&tabs=HTTP'
          inputs: {
            headers: {
              Authorization: 'Basic @{base64(concat(body(\'Get_PAT_Token\')?[\'value\'],\':\'))}'
            }
            method: 'GET'
            uri: '@{variables(\'project_url\')}/_apis/git/pullrequests?api-version=6.0'
          }
          operationOptions: 'DisableAsyncPattern, SuppressWorkflowHeaders'
          runAfter: {
            Get_PAT_Token: [
              'Succeeded'
            ]
          }
          type: 'Http'
        }
        Get_PAT_Token: {
          inputs: {
            host: {
              connection: {
                name: '@parameters(\'$connections\')[\'keyvault\'][\'connectionId\']'
              }
            }
            method: 'get'
            path: '/secrets/@{encodeURIComponent(\'azdoAccessToken\')}/value'
          }
          runAfter: {
            Init_Email_Body: [
              'Succeeded'
            ]
          }
          type: 'ApiConnection'
        }
        Init_Email_Body: {
          inputs: {
            variables: [
              {
                name: 'email_body_html'
                type: 'string'
              }
            ]
          }
          runAfter: {
            Init_Email_Recipients: [
              'Succeeded'
            ]
          }
          type: 'InitializeVariable'
        }
        Init_Email_Recipients: {
          inputs: {
            variables: [
              {
                name: 'email_recipients'
                type: 'array'
                value: [for email in email_addresses: { email: email }]
              }
            ]
          }
          runAfter: {
            Init_Project_URL: [
              'Succeeded'
            ]
          }
          type: 'InitializeVariable'
        }
        Init_Project_URL: {
          inputs: {
            variables: [
              {
                name: 'project_url'
                type: 'string'
                value: project_url
              }
            ]
          }
          runAfter: {}
          type: 'InitializeVariable'
        }
        Map_PR_Entries: {
          inputs: {
            from: '@body(\'Parse_GetPullRequests_Response\')?[\'value\']'
            select: {
              author: '@item()?[\'createdBy\']?[\'displayName\']'
              isDraft: '@item()?[\'isDraft\']'
              isWorkInProgress: '@or(startsWith(item().title, \'WIP \'), startsWith(item().title, \'WIP: \'))'
              projectName: '@{item()?[\'repository\']?[\'project\']?[\'name\']}'
              pullRequestId: '@item()?[\'pullRequestId\']'
              repositoryName: '@{item()?[\'repository\']?[\'name\']}'
              title: '@item()?[\'title\']'
              url: '@{variables(\'project_url\')}_git/@{item()?[\'repository\']?[\'name\']}/pullrequest/@{item()?[\'pullRequestId\']}'
            }
          }
          runAfter: {
            Parse_GetPullRequests_Response: [
              'Succeeded'
            ]
          }
          type: 'Select'
        }
        Parse_GetPullRequests_Response: {
          inputs: {
            content: '@body(\'Get_All_Open_PRs\')'
            schema: {
              properties: {
                count: {
                  type: 'integer'
                }
                value: {
                  items: {
                    properties: {
                      createdBy: {
                        properties: {
                          _links: {
                            properties: {
                              avatar: {
                                properties: {
                                  href: {
                                    type: 'string'
                                  }
                                }
                                type: 'object'
                              }
                            }
                            type: 'object'
                          }
                          descriptor: {
                            type: 'string'
                          }
                          displayName: {
                            type: 'string'
                          }
                          id: {
                            type: 'string'
                          }
                          imageUrl: {
                            type: 'string'
                          }
                          uniqueName: {
                            type: 'string'
                          }
                          url: {
                            type: 'string'
                          }
                        }
                        type: 'object'
                      }
                      creationDate: {
                        type: 'string'
                      }
                      description: {
                        type: 'string'
                      }
                      isDraft: {
                        type: 'boolean'
                      }
                      lastMergeCommit: {
                        properties: {
                          commitId: {
                            type: 'string'
                          }
                          url: {
                            type: 'string'
                          }
                        }
                        type: 'object'
                      }
                      lastMergeSourceCommit: {
                        properties: {
                          commitId: {
                            type: 'string'
                          }
                          url: {
                            type: 'string'
                          }
                        }
                        type: 'object'
                      }
                      lastMergeTargetCommit: {
                        properties: {
                          commitId: {
                            type: 'string'
                          }
                          url: {
                            type: 'string'
                          }
                        }
                        type: 'object'
                      }
                      mergeId: {
                        type: 'string'
                      }
                      mergeStatus: {
                        type: 'string'
                      }
                      pullRequestId: {
                        type: 'integer'
                      }
                      repository: {
                        properties: {
                          id: {
                            type: 'string'
                          }
                          name: {
                            type: 'string'
                          }
                          project: {
                            properties: {
                              id: {
                                type: 'string'
                              }
                              lastUpdateTime: {
                                type: 'string'
                              }
                              name: {
                                type: 'string'
                              }
                              state: {
                                type: 'string'
                              }
                              visibility: {
                                type: 'string'
                              }
                            }
                            type: 'object'
                          }
                          url: {
                            type: 'string'
                          }
                        }
                        type: 'object'
                      }
                      reviewers: {
                        type: 'array'
                      }
                      sourceRefName: {
                        type: 'string'
                      }
                      status: {
                        type: 'string'
                      }
                      supportsIterations: {
                        type: 'boolean'
                      }
                      targetRefName: {
                        type: 'string'
                      }
                      title: {
                        type: 'string'
                      }
                      url: {
                        type: 'string'
                      }
                    }
                    required: [
                      'repository'
                      'pullRequestId'
                      'codeReviewId'
                      'status'
                      'createdBy'
                      'creationDate'
                      'title'
                      'sourceRefName'
                      'targetRefName'
                      'isDraft'
                      'mergeId'
                      'url'
                    ]
                    type: 'object'
                  }
                  type: 'array'
                }
              }
              type: 'object'
            }
          }
          runAfter: {
            Get_All_Open_PRs: [
              'Succeeded'
            ]
          }
          type: 'ParseJson'
        }
        Post_PR_Bulletin_to_Channel: {
          inputs: {
            body: {
              text: '@{variables(\'email_body_html\')}'
            }
            method: 'POST'
            uri: teams_channel_webhook_url
          }
          runAfter: {
            Condition: [
              'Succeeded'
            ]
          }
          type: 'Http'
        }
        Send_PR_Bulletin_Email: {
          inputs: {
            body: {
              content: {
                html: '@{variables(\'email_body_html\')}'
                subject: '${email_subject_prefix} (@{length(body(\'Filter_out_Draft_and_WIP_PRs\'))}): @{convertFromUtc(utcNow(), \'GMT Standard Time\', \'f\')}'
              }
              disableUserEngagementTracking: true
              importance: 'high'
              recipients: {
                to: '@variables(\'email_recipients\')'
              }
              sender: '${email_services_sender.properties.username}@${email_services_managed_domain.properties.fromSenderDomain}'
            }
            host: {
              connection: {
                name: '@parameters(\'$connections\')[\'acsemail\'][\'connectionId\']'
              }
            }
            method: 'post'
            path: '/emails:send'
            queries: {
              'api-version': '2021-10-01-preview'
            }
          }
          runAfter: {
            Condition: [
              'Succeeded'
            ]
          }
          type: 'ApiConnection'
        }
      }
      contentVersion: '1.0.0.0'
      outputs: {}
      parameters: {
        '$connections': {
          defaultValue: {}
          type: 'Object'
        }
      }
      triggers: {
        'Every_weekday_9am,_11am,_2pm_and_4pm': {
          evaluatedRecurrence: {
            frequency: 'Week'
            interval: 1
            schedule: {
              hours: [
                '9'
                '14'
                '11'
                '16'
              ]
              minutes: [
                0
              ]
              weekDays: [
                'Monday'
                'Tuesday'
                'Wednesday'
                'Thursday'
                'Friday'
              ]
            }
            timeZone: 'GMT Standard Time'
          }
          recurrence: {
            frequency: 'Week'
            interval: 1
            schedule: {
              hours: [
                '9'
                '14'
                '11'
                '16'
              ]
              minutes: [
                0
              ]
              weekDays: [
                'Monday'
                'Tuesday'
                'Wednesday'
                'Thursday'
                'Friday'
              ]
            }
            timeZone: 'GMT Standard Time'
          }
          type: 'Recurrence'
        }
      }
    }
    parameters: {
      '$connections': {
        value: {
          acsemail: {
            connectionId: communications_service_connection.id
            connectionName: 'acsemail'
            id: subscriptionResourceId('Microsoft.Web/locations/managedApis', region, communications_service_connection.name)
          }
          keyvault: {
            connectionId: keyvault_connection.id
            connectionName: 'keyvault'
            connectionProperties: {
              authentication: {
                type: 'ManagedServiceIdentity'
              }
            }
            id: subscriptionResourceId('Microsoft.Web/locations/managedApis', region, keyvault_connection.name)
          }
        }
      }
    }
    state: 'Enabled'
  }
}
