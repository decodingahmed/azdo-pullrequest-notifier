# Bicep deployment of Azure DevOps Pull Request Notifier

The Pull Request Notifier is logic app workflow that fetches open PRs using the [Azure DevOps REST API](https://learn.microsoft.com/en-us/rest/api/azure/devops/git/pull-requests/get-pull-requests-by-project?view=azure-devops-rest-6.0&tabs=HTTP) from an Azure DevOps project and send out reminder emails to prompt developers to review PRs ready for review.

The [Recurrence](https://learn.microsoft.com/en-gb/azure/connectors/connectors-native-recurrence?tabs=consumption) triggers the workflow to begin executing at specific times of the day on each weekday (Mon-Fri).

Draft PRs and PRs with "WIP" prefixed to the title are filtered out from the bulletin in case the authors are not ready or still working on their PRs.

# Usage

## Pre-requisites
1. Azure Subscription.
2. Azure account that can deploy to the subscription.
3. Azure CLI installed.

## Deployment steps

1. Ensure that your Azure CLI is logged into your tenant and subscription is set.
   ```bash
   az login --tenant <TENANT_ID>
   az account set --subscription <NAME_OF_SUBSCRIPTION>
   ```

2. Create your project specific configuration:
   1. Duplicate the `prnotifier.bicepparam.template` file.
   2. Rename the new file and remove the `.template` from the name.
   3. Set the parameters in file:
      | Parameter | Description |
      |-|-|
      | `resource_prefix` | Prefix added to all resources deployed. |
      | `azdo_project_url` | URL of the Azure DevOps **project**. |
      | `azdo_access_token` | Personal Access Token used to call the Azure DevOps API. |
      | `azdo_repository_names` | (Optional) An array of repository names to watch. If empty, all repositories in the project are watched. |
      | `teams_channel_webhook_url` | URL to the Teams channel webhook where the PR notification will be posted to. Follow instructions [here](https://learn.microsoft.com/en-us/microsoftteams/platform/webhooks-and-connectors/how-to/add-incoming-webhook?tabs=newteams%2Cdotnet#create-an-incoming-webhook) to create one. |
      | `email_addresses` | An array of recipient email addresses that the PR notification will be sent to. |
      | `email_subject_prefix` | Prefix for the email subject line. E.g. `[YOUR_PREFIX_HERE] (1): Friday, October 11, 2024 11:11 PM`. Defaults to `Pull Requests`. |

3. Deploy the PR Notifier with the following command:
   ```bash
   az deployment sub create `
     --name pr-notifier-deployment `
     --location uksouth `
     --parameters file/from/previous/step.bicepparam
   ```
