# Azure DevOps Pull Request Notifier

The Pull Request Notifier fetches open PRs using the [Azure DevOps REST API](https://learn.microsoft.com/en-us/rest/api/azure/devops/git/pull-requests/get-pull-requests-by-project?view=azure-devops-rest-6.0&tabs=HTTP) and sends out reminder emails to prompt developers to review open PRs.

The [Recurrence](https://learn.microsoft.com/en-gb/azure/connectors/connectors-native-recurrence?tabs=consumption) triggers the workflow at specific times of the day on each weekday (Mon-Fri).

Draft PRs and PRs with "WIP" prefixed to the title are filtered out from the notification to allow authors to filter out their PR if they are are not ready or still working on their PRs.

# Implementations

1. Bicep: follow [instructions](./bicep/README.md) to deploy this using Bicep
2. Terraform: coming soon!

# Future plans

1. Configurable CI/CD pipelines to easily deploy changes to the PR notifier
2. Design a better development lifecycle experience:
   - Developer could make changes in the Azure Portal
   - Copy-paste the workflow JSON into Git 
   - Re-run the deployment
3. Reconsider use of Logic Apps as making changes is not user- or developer-friendly.
   - Re-create and consider other free (or super cheap) compute resources to host custom code in.
   - Azure Function?
   - Container Instance?