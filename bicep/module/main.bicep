targetScope = 'subscription'

@description('The prefix to add to all resource names.')
param resource_prefix string

@description('The deployment region for resources.')
param region string = 'uksouth'

@description('The email addresses to send the PR Notification to.')
param email_addresses array

@description('The prefix of the email subject.')
param email_subject_prefix string = 'PR Bulletin'

@description('The URL of the Azure DevOps project.')
param azdo_project_url string

@description('The Azure DevOps Personal Access Token to request the list of Pull Requests.')
@secure()
param azdo_access_token string

@description('The list of Azure DevOps repositories to filter the PRs from.')
param azdo_repository_names array = []

@description('The URL of the Teams Channel Webhook to post the PR Notification to.')
param teams_channel_webhook_url string

resource rg 'Microsoft.Resources/resourceGroups@2021-04-01' = {
  name: '${resource_prefix}-prnotifier-rg'
  location: region
}

module notifier 'notifier.bicep' = {
  name: 'notifier'
  scope: resourceGroup(rg.name)
  params: {
    resource_prefix: resource_prefix
    region: region
    email_addresses: email_addresses
    email_subject_prefix: email_subject_prefix
    azdo_project_url: azdo_project_url
    azdo_access_token: azdo_access_token
    azdo_repository_names: azdo_repository_names
    teams_channel_webhook_url: teams_channel_webhook_url
  }
}
