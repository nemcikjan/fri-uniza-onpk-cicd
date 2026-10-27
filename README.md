# fri-uniza-onpk-cicd

Lab material for the ONPK course at FRI UNIZA, lecture 7: CI/CD with **Tekton** and **FluxCD**.

You build, push and deploy a small Node.js upload app (with MongoDB) in two ways:

- **Lab 1, Demo 1:** one Tekton pipeline does everything: clone, build with buildah, push to the GitHub Container Registry (ghcr.io), deploy with Helm.
- **Lab 2, Demo 2 (GitOps):** Tekton builds the image and commits the new image tag to Git. Flux watches the repo and deploys the Helm release. Rollback is a `git revert`.

**Start here: [RUNBOOK.md](RUNBOOK.md).** You need a GitHub account and a Kubernetes cluster (provided in the lab). Fork this repo first (RUNBOOK 1.4): the Lab 2 pipeline pushes commits to your own copy, and images go to `ghcr.io/<your-user>/fri-uniza-onpk-cicd`.

## Repo layout

```
app/                         Node.js upload app + Dockerfile
helm/uploadapp/              Helm chart for the app and its MongoDB (official `mongo` image)
  values-uploadapp.yaml      values the pipelines and Flux deploy with
cicd/hello-world/            first Tekton Task + TaskRun
cicd/upload-app-demo/
  01-creds-docker.yaml       how to create the ghcr.io push/pull secrets (no credentials in Git)
  02-creds-github.yaml       how to create the Git deploy-key secret (no credentials in Git)
  03-rbac.yml                ServiceAccount + RBAC the pipelines run as
  10-pipeline-push.yaml      Demo 1 pipeline: clone, build info, buildah, helm deploy
  11-pipeline-push-run.yaml  Demo 1 PipelineRun
  20-fluxcd-capacitor.yaml   Capacitor (Flux UI), installed the Flux way
  21-pipeline-gitops.yaml    Demo 2 pipeline: clone, build info, buildah, bump tag, git push
  22-pipeline-gitops-run.yaml  Demo 2 PipelineRun
  23-fluxcd-uploadapp.yaml   Flux GitRepository + HelmRelease for the app
cicd/github-trigger/         optional: Tekton Triggers EventListener for GitHub PR events
RUNBOOK.md                   step-by-step instructions for both labs
```

The files contain the placeholder `<GITHUB_USER>` (your GitHub user, lowercase). RUNBOOK 1.4 step 2 replaces it with one command.

## Versions

Tekton Pipelines v1.17.1, Tekton Dashboard v0.73.0, Tekton Triggers v0.37.2, catalog tasks git-clone 0.9 and buildah 0.9, Flux v2 (`source.toolkit.fluxcd.io/v1`, `helm.toolkit.fluxcd.io/v2`), MongoDB `mongo:8.0` (official image).
