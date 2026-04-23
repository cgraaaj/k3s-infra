# Renovate Bot - Self-Hosted

Automated dependency update bot running as a Kubernetes CronJob.
Scans ArgoCD Application manifests and Helm values for version bumps,
then creates Pull Requests on GitHub.

## Setup

1. Create a GitHub Personal Access Token (classic) at:
   https://github.com/settings/tokens

   Required scopes: `repo` (full control of private repositories)

2. Update the token in the secret:
   ```bash
   kubectl create secret generic renovate-github-token \
     --namespace renovate \
     --from-literal=token=ghp_YOUR_TOKEN_HERE \
     --dry-run=client -o yaml | kubectl apply -f -
   ```

3. Deploy:
   ```bash
   kubectl apply -f renovate/namespace.yaml
   kubectl apply -f renovate/configmap.yaml
   kubectl apply -f renovate/secret-github-token.yaml
   kubectl apply -f renovate/cronjob.yaml
   ```

4. Test with a manual run:
   ```bash
   kubectl create job renovate-test --from=cronjob/renovate -n renovate
   kubectl logs -f -n renovate job/renovate-test
   ```

## Schedule

Runs every 6 hours by default. The `renovate.json` in the repo root
configures the schedule for PR creation (weekends only).

## What It Updates

- Helm chart versions in ArgoCD Application manifests (`targetRevision`)
- Container image tags in `values.yaml` files
- Kubernetes manifest image references

## Auto-merge Policy

- Patch updates: auto-merged
- Minor updates: auto-merged (dev cluster)
- Major updates: require manual PR review
- Longhorn/Vault: require manual review for minor+major (critical infra)
