# Lab 7 Runbook: CI/CD with Tekton and FluxCD

- **Lab 1 (today):** tools, Tekton, hello world, catalog tasks, credentials, RBAC, Demo 1 (CI + CD in one Tekton pipeline).
- **Lab 2 (next week):** Demo 2 (Tekton CI + Flux CD, GitOps), closing the loop, rollback, optional Tekton Triggers and Flagger, cleanup.

You work in **your own GitHub copy of this repo** (a fork, see 1.4). The Lab 2 pipeline pushes commits to that repo with your own deploy key, so it can't be the shared course repo.

You only need a GitHub account: the pipelines push the app image to the GitHub Container Registry (`ghcr.io/<GITHUB_USER>/fri-uniza-onpk-cicd`).

All manifests in `cicd/` are ready to use. The only edit you make is your account name: the placeholder `<GITHUB_USER>` (your GitHub user name, **in lowercase**, because image names must be lowercase). 1.4 step 2 replaces it in all files with one command.

Commands are bash, run from the root of your clone unless stated otherwise. On Windows, use **Git Bash** or WSL2 bash.

---

# PART 1: LAB 1 (27.10.2026)

## 1.1 Install the tools

You need kubectl, helm 3, tkn (Tekton CLI), flux (for lab 2), and git + ssh.

| OS | Install |
|---|---|
| macOS (Homebrew) | `brew install kubectl helm fluxcd/tap/flux tektoncd-cli git` |
| Windows (Chocolatey, run as Administrator) | `choco install kubernetes-cli kubernetes-helm flux tektoncd-cli git` (or the winget/scoop equivalents) |
| Linux | kubectl: [kubernetes.io/docs/tasks/tools](https://kubernetes.io/docs/tasks/tools/). helm: `curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 \| bash`. tkn: release tarball from [github.com/tektoncd/cli/releases](https://github.com/tektoncd/cli/releases). flux: `curl -s https://fluxcd.io/install.sh \| sudo bash`. git: your distro's package |

Check them:

```bash
kubectl version --client
helm version --short
tkn version
flux version --client
git --version
```

## 1.2 Check your cluster

Your cluster and kubectl context are already set up. Check that you're pointing at the lab cluster and that it has what the lab needs:

```bash
kubectl config current-context     # must be your lab cluster
kubectl get nodes                  # all nodes Ready
kubectl get ingressclass           # must list "nginx"
kubectl get storageclass           # one must be marked "(default)"
```

- The `nginx` IngressClass is used by the app's Ingress.
- The default StorageClass provides the volumes the pipelines create for their workspaces.

If something is missing, ask the lecturer. Don't run lab commands against any other cluster.

## 1.3 Install Tekton Pipelines v1.17.1 and the Dashboard v0.73.0

```bash
kubectl apply -f https://infra.tekton.dev/tekton-releases/pipeline/previous/v1.17.1/release.yaml
kubectl wait -n tekton-pipelines --for=condition=ready pod --all --timeout=300s

# Dashboard, full (read/write) version
kubectl apply -f https://infra.tekton.dev/tekton-releases/dashboard/previous/v0.73.0/release-full.yaml
kubectl -n tekton-pipelines rollout status deploy/tekton-dashboard --timeout=180s
```

Open the Dashboard. In a separate terminal, leave this running:

```bash
kubectl -n tekton-pipelines port-forward svc/tekton-dashboard 9097:9097
# open http://localhost:9097
```

Wait until `tekton-pipelines-webhook` is Ready before applying any Task or Pipeline. Otherwise you get `failed calling webhook "webhook.pipeline.tekton.dev" … connection refused`.

## 1.4 Get the lab repo

### 1. Fork it (or copy it to your own repo)

**Option A: fork (recommended).** On GitHub, open this repo and click **Fork**. Keep the name `fri-uniza-onpk-cicd`. Then clone your fork:

```bash
git clone git@github.com:<GITHUB_USER>/fri-uniza-onpk-cicd.git ~/fri-uniza-onpk-cicd
cd ~/fri-uniza-onpk-cicd
```

**Option B: your own repo.** Create an **empty** repo named `fri-uniza-onpk-cicd` on GitHub (no README), then:

```bash
git clone https://github.com/plectrum-engineering/fri-uniza-onpk-cicd.git ~/fri-uniza-onpk-cicd
cd ~/fri-uniza-onpk-cicd
git remote set-url origin git@github.com:<GITHUB_USER>/fri-uniza-onpk-cicd.git
git push -u origin main
```

If you pick another repo name, also replace `fri-uniza-onpk-cicd` in the `app/`, `cicd/` and `helm/` files after step 2.

**Public or private?** Both work. A fork of a public repo is always public. If you want your copy private, use Option B and create the empty repo as **Private**. Nothing else changes:
- The pipelines (git-clone, git push) and Flux reach the repo through your SSH deploy key (1.6 step 3), which works for private repos.
- The image package on ghcr.io is private by default either way, and the cluster pulls it with the `ghcr-pull` secret (1.7).
- Everything else the lab downloads (Tekton, catalog tasks, Flux, the MongoDB image) is public.

### 2. Set your GitHub user

The files under `app/`, `cicd/` and `helm/` contain the placeholder `<GITHUB_USER>` (repo URLs, image name `ghcr.io/<GITHUB_USER>/fri-uniza-onpk-cicd`, the image's source label). Replace it everywhere at once (works with GNU and macOS sed):

```bash
GITHUB_USER=your-github-user          # CHANGE, lowercase (e.g. JanNovak -> jannovak)

grep -rlI '<GITHUB_USER>' app cicd helm | xargs sed -i.bak "s/<GITHUB_USER>/${GITHUB_USER}/g"
find app cicd helm -name '*.bak' -delete

grep -rnI '<GITHUB_USER>' app cicd helm    # no output = done
git diff --stat

git add app cicd helm
git commit -m "Set my GitHub user"
git push
```

### 3. Hello world (Task / TaskRun)

```bash
kubectl apply -f cicd/hello-world/task.yml
kubectl apply -f cicd/hello-world/task-run.yml

kubectl get taskrun hello-task-run
kubectl wait --for=condition=Succeeded taskrun/hello-task-run --timeout=180s
kubectl logs --selector=tekton.dev/taskRun=hello-task-run
# Hello World
```

The same with tkn:

```bash
tkn task list
tkn taskrun list
tkn taskrun describe hello-task-run
tkn taskrun logs hello-task-run            # -f to follow
# start a new run of the same Task without YAML and stream the logs:
tkn task start hello --showlog
```

## 1.5 Install the catalog tasks

Install `git-clone` and `buildah` straight from the Tekton catalog on GitHub (the old Tekton Hub and `tkn hub install` no longer work):

```bash
kubectl apply -f https://raw.githubusercontent.com/tektoncd/catalog/main/task/git-clone/0.9/git-clone.yaml
kubectl apply -f https://raw.githubusercontent.com/tektoncd/catalog/main/task/buildah/0.9/buildah.yaml
tkn task list          # hello, git-clone, buildah
```

- `git-clone` clones a repo into a workspace.
- `buildah` builds a container image from a Dockerfile and pushes it to a registry. Its build step runs privileged.

## 1.6 Prerequisites: GitHub token, deploy key

### 1. Look at `helm/uploadapp/values-uploadapp.yaml`

These are the values the pipelines and Flux deploy with. Besides your image name (set in 1.4 step 2), two settings differ from the chart defaults:
- `imagePullSecrets: [{name: ghcr-pull}]`: new GHCR packages are private, so the cluster needs credentials to pull your image (secret created in 1.7).
- `mongodb.auth`: the MongoDB root user. The app connects with `appbackendDb.user` / `password`, so keep the two in sync.

```yaml
mongodb:
  auth:
    rootUser: mongoroot
    rootPassword: mongotest
```

MongoDB itself comes from `helm/uploadapp/templates/mongodb.yaml`: a single-pod StatefulSet `uploadapp-mongodb` running the official `mongo:8.0` image, with TCP probes and no persistent volume (data is lost when the pod restarts). The image and init scripts are set under `mongodb:` in `values.yaml`.

Why MongoDB matters: `app/src/middleware/upload.js` connects to MongoDB when the app starts. If MongoDB isn't reachable, the Node process dies, the pod crash-loops and `helm --wait` times out.

### 2. Create a GitHub token for the container registry

Your code lives in your GitHub repo, and the image the pipeline builds lives next to it in the GitHub Container Registry, `ghcr.io/<GITHUB_USER>/fri-uniza-onpk-cicd`. buildah pushes there with a GitHub **classic** personal access token (PAT). Fine-grained tokens don't work with the container registry.

1. Open https://github.com/settings/tokens/new?scopes=write:packages&description=onpk-lab-ghcr. This pre-fills the form. Manual path: GitHub → your avatar → **Settings** → **Developer settings** → **Personal access tokens** → **Tokens (classic)** → **Generate new token** → **Generate new token (classic)**.
2. Note: `onpk-lab-ghcr`. Expiration: 30 days.
3. Scopes: only **`write:packages`** (this also selects `read:packages`). Don't tick `repo` or anything else; git access goes through the deploy key, not this token.
4. Click **Generate token** and copy it (`ghp_…`). GitHub shows it only once. If you lose it, delete it and generate a new one.

Check that the token works and has the right scope (paste it when prompted; it isn't echoed):

```bash
read -rs GHCR_TOKEN
curl -sI -H "Authorization: Bearer $GHCR_TOKEN" https://api.github.com/user | grep -i '^x-oauth-scopes'
# x-oauth-scopes: write:packages     (read:packages may also be listed)
unset GHCR_TOKEN
```

No `x-oauth-scopes` line, or `HTTP 401`: the token is wrong or expired.

The same token pushes the image (buildah) and pulls it (the cluster); both secrets are created in 1.7. The first push creates a **private** package `fri-uniza-onpk-cicd` under your account. The `LABEL org.opencontainers.image.source` in `app/Dockerfile` links the package to your repo, so you'll see it on your repo page under **Packages**.

Treat the token like a password: don't commit it, don't paste it into YAML files in the repo, and delete it after the course (see Cleanup).

### 3. Create a GitHub deploy key with write access

Keep all credentials outside the repo, in `~/lab-secrets`:

```bash
mkdir -p ~/lab-secrets && chmod 700 ~/lab-secrets
ssh-keygen -t ed25519 -N '' -C "tekton-flux-upload-app" -f ~/lab-secrets/upload-app-deploy
cat ~/lab-secrets/upload-app-deploy.pub
```

In GitHub: your repo → Settings → Deploy keys → Add deploy key → paste the `.pub` content → **tick "Allow write access"**. The lab 2 pipeline pushes commits with this key.

```bash
ssh-keyscan github.com > ~/lab-secrets/known_hosts 2>/dev/null
# check that the key works
ssh -i ~/lab-secrets/upload-app-deploy -o IdentitiesOnly=yes -o UserKnownHostsFile=~/lab-secrets/known_hosts -T git@github.com
# expected: "Hi <GITHUB_USER>/fri-uniza-onpk-cicd! You've successfully authenticated..."
```

## 1.7 Secrets and RBAC

Create the secrets with `kubectl create secret … --from-file`. The repo files `01-creds-docker.yaml` / `02-creds-github.yaml` only document the result; never commit real credentials.

### 1. Container registry credentials (ghcr.io)

Two secrets from the same token (1.6 step 2):
- `docker-credentials`: a `config.json` for **pushing**. The buildah task mounts it as its `dockerconfig` workspace, so `config.json` must be at the root of the secret (it is). The registry key is `ghcr.io`.
- `ghcr-pull`: a `docker-registry` secret for **pulling**. `values-uploadapp.yaml` references it as `imagePullSecrets`, for both the Demo 1 Helm deploy and Flux.

```bash
GITHUB_USER=<GITHUB_USER>
read -rs GHCR_TOKEN               # paste the classic PAT, press Enter
AUTH=$(printf '%s:%s' "$GITHUB_USER" "$GHCR_TOKEN" | base64 | tr -d '\n')
printf '{"auths":{"ghcr.io":{"auth":"%s"}}}\n' "$AUTH" > ~/lab-secrets/config.json

kubectl create secret generic docker-credentials \
  --from-file=config.json="$HOME/lab-secrets/config.json"
kubectl create secret docker-registry ghcr-pull \
  --docker-server=ghcr.io --docker-username="$GITHUB_USER" --docker-password="$GHCR_TOKEN"
unset GHCR_TOKEN AUTH
```

PowerShell alternative for the `auth` value: `[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("user:token"))`. Or run the bash commands in Git Bash.

Alternative to the pull secret: after the first successful push (1.8), make the package public once. GitHub → your profile → **Packages** → `fri-uniza-onpk-cicd` → **Package settings** → **Change visibility** → Public. The `ghcr-pull` secret is then not needed (leave it in place, it does no harm).

### 2. Git credentials

One secret holds everything:
- `id_ed25519`: used by the git-clone task and by the lab 2 git-push step.
- `identity` + `known_hosts`: the keys Flux's GitRepository expects (lab 2).

```bash
kubectl create secret generic git-credentials \
  --from-file=id_ed25519="$HOME/lab-secrets/upload-app-deploy" \
  --from-file=identity="$HOME/lab-secrets/upload-app-deploy" \
  --from-file=known_hosts="$HOME/lab-secrets/known_hosts"
```

If you use an RSA key instead, name the first key `id_rsa`.

### 3. RBAC for the pipeline service account

The pipelines run as `pipeline-sa`, which needs permission to deploy (and uninstall) the Helm chart. `cicd/upload-app-demo/03-rbac.yml` creates the ServiceAccount, a ClusterRole for the chart's objects (services, secrets, configmaps, PVCs, deployments, statefulsets, ingresses, …) and the binding. Read it, then apply it:

```bash
kubectl apply -f cicd/upload-app-demo/03-rbac.yml
kubectl auth can-i list pods --as system:serviceaccount:default:pipeline-sa      # yes
```

Note: this ClusterRole gives `pipeline-sa` cluster-wide access to secrets. Fine for a lab cluster, not for production.

## 1.8 Demo 1: CI + CD in one Tekton pipeline

The pipeline `cicd/upload-app-demo/10-pipeline-push.yaml`:

1. `fetch-source` (catalog `git-clone`): clones your repo into the `shared-data` workspace, using the deploy key from `git-credentials`.
2. `add-build-info`: writes `app/src/.env` with `BUILD_VERSION` (the image tag) and `BUILD_TIME`. The app shows them at `/info`.
3. `buildah-build` (catalog `buildah`): builds `app/Dockerfile` and pushes `<image-name>:<image-tag>` to ghcr.io with `docker-credentials`.
4. `deploy-app`: `helm lint`, then `helm upgrade --install uploadapp … --set image.repository=… --set image.tag=… --wait`.

Read the file, then look at the PipelineRun `cicd/upload-app-demo/11-pipeline-push-run.yaml` (shown here with placeholders; yours has your names since 1.4 step 2):

```yaml
apiVersion: tekton.dev/v1beta1
kind: PipelineRun
metadata:
  generateName: clone-build-push-deploy-run-
spec:
  serviceAccountName: pipeline-sa
  pipelineRef:
    name: clone-build-push-deploy
  podTemplate:
    securityContext:
      fsGroup: 65532
  params:
    - name: repo-url
      value: git@github.com:<GITHUB_USER>/fri-uniza-onpk-cicd.git    # your fork (SSH url)
    - name: repo-revision
      value: "main"
    - name: image-name
      value: "ghcr.io/<GITHUB_USER>/fri-uniza-onpk-cicd"              # lowercase
    - name: image-tag
      value: "1.0.0"
    - name: build-extra-args
      value: ""
  workspaces:
    - name: shared-data
      volumeClaimTemplate:
        spec:
          accessModes:
            - ReadWriteOnce
          resources:
            requests:
              storage: 1Gi
    - name: git-credentials
      secret:
        secretName: git-credentials
    - name: dockerconfig
      secret:
        secretName: docker-credentials
```

- `volumeClaimTemplate` creates a fresh 1Gi volume for each run from the default StorageClass.
- `fsGroup: 65532` lets the non-root git-clone step write to that volume.

### 1. Run it

```bash
kubectl apply  -f cicd/upload-app-demo/10-pipeline-push.yaml
kubectl create -f cicd/upload-app-demo/11-pipeline-push-run.yaml     # create, not apply (generateName)

tkn pipelinerun list
tkn pipelinerun logs -f --last
# or watch it in the Dashboard: http://localhost:9097
```

The first run takes a few minutes (image pulls, `npm install`, MongoDB start).

### 2. Optional: start the pipeline with tkn instead of the run YAML

```bash
cat > /tmp/pvc.yaml <<'EOF'
spec:
  accessModes: [ReadWriteOnce]
  resources: {requests: {storage: 1Gi}}
EOF
cat > /tmp/podtemplate.yaml <<'EOF'
securityContext:
  fsGroup: 65532
EOF
tkn pipeline start clone-build-push-deploy \
  -p repo-url=git@github.com:<GITHUB_USER>/fri-uniza-onpk-cicd.git -p repo-revision=main \
  -p image-name=ghcr.io/<GITHUB_USER>/fri-uniza-onpk-cicd -p image-tag=1.0.1 \
  -w name=shared-data,volumeClaimTemplateFile=/tmp/pvc.yaml \
  -w name=git-credentials,secret=git-credentials \
  -w name=dockerconfig,secret=docker-credentials \
  --serviceaccount pipeline-sa --pod-template /tmp/podtemplate.yaml --showlog
```

## 1.9 Verify the app

```bash
kubectl get pods,svc,ingress
```

You can reach the app in three ways. The lecturer will give you `<INGRESS_ADDRESS>` (the ingress controller's address, with port if it isn't 80).

**Option A: curl with a Host header**

```bash
curl -s -H 'Host: uploadapp.mydomain.local' http://<INGRESS_ADDRESS>/info
# {"BuildVersion":"1.0.0","BuildTime":"..."}
curl -s -H 'Host: uploadapp.mydomain.local' http://<INGRESS_ADDRESS>/files
# {"message":"No files found!"}   (MongoDB reachable)
```

On Windows PowerShell use `curl.exe` (plain `curl` is an alias there), or use Git Bash.

**Option B: hosts file + browser**

Add a line `<INGRESS_IP> uploadapp.mydomain.local` to your hosts file (the IP part of `<INGRESS_ADDRESS>`):
- Linux and other Unix-like systems: `/etc/hosts`, e.g. `echo '<INGRESS_IP> uploadapp.mydomain.local' | sudo tee -a /etc/hosts`
- Windows: `C:\Windows\System32\drivers\etc\hosts`, edit as Administrator

Then open `http://uploadapp.mydomain.local/` (add `:<port>` if `<INGRESS_ADDRESS>` has one). Upload a PNG/JPG, then open `/files` and `/info`.

**Option C: port-forward (always works)**

```bash
kubectl port-forward svc/uploadapp 9080:9080
# in another terminal:
curl -s http://localhost:9080/info
# browser: http://localhost:9080/
```

Exercise: rerun the pipeline with `image-tag=1.0.1` (1.8 step 2, or edit the tag in `11-pipeline-push-run.yaml` and `kubectl create` it again) and watch `/info` change.

## 1.10 Troubleshooting (both labs)

```bash
# Tekton
tkn pipelinerun list
tkn pipelinerun describe --last          # which task failed, and why
tkn pipelinerun logs -f --last           # all steps; add -t <task> for one task
tkn taskrun list ; tkn taskrun logs -f <taskrun>
kubectl get pipelineruns,taskruns
kubectl get pods                          # each TaskRun = 1 pod, each step = 1 container "step-<name>"
kubectl describe pod <pod>
kubectl logs <pod> -c step-<step-name>
kubectl get events --sort-by=.lastTimestamp | tail -30
kubectl -n tekton-pipelines logs deploy/tekton-pipelines-controller --tail=50

# app / helm
helm list -A ; helm status uploadapp ; helm history uploadapp
kubectl logs deploy/uploadapp ; kubectl logs statefulset/uploadapp-mongodb
kubectl get ingress

# Flux (lab 2)
flux get all -n default                  # the app objects live in "default"; flux defaults to flux-system
flux get sources git -n default ; flux get helmreleases -n default
flux logs --level=error
kubectl describe helmrelease uploadapp
```

| Symptom | Cause / fix |
|---|---|
| `failed calling webhook "webhook.pipeline.tekton.dev" … connection refused` | Tekton webhook not Ready yet. `kubectl -n tekton-pipelines get pods`, wait, retry |
| fetch-source / buildah fails on `<GITHUB_USER>` in a URL or image name | Placeholder not replaced: redo 1.4 step 2, commit, push |
| `Host key verification failed` in fetch-source | `known_hosts` missing or wrong in `git-credentials` |
| `Permission denied (publickey)` | Deploy key not added, wrong repo, or the secret key isn't named `id_ed25519` / `id_rsa` |
| git-push `ERROR: The key you are authenticating with has been marked as read only` | Deploy key needs **Allow write access** |
| buildah `unauthorized` / `denied` / `permission_denied: The token provided does not match expected scopes` | Token is not a classic PAT with `write:packages`, `config.json` key is not `ghcr.io`, or the image name is not `ghcr.io/<your lowercase user>/…` |
| buildah `invalid reference format: repository name must be lowercase` | Your user in the image name has uppercase letters: use lowercase in 1.4 step 2 |
| App pod `ImagePullBackOff` / `ErrImagePull` … `unauthorized` or `denied` | `ghcr-pull` secret missing or wrong (1.7 step 1), or make the package public |
| PVC `Pending` | Normal until the first pod is scheduled. If it stays Pending, check `kubectl get storageclass` has a default |
| helm `context deadline exceeded` | Usually MongoDB not Ready: check the mongodb pod and events |
| MongoDB `ImagePullBackOff` | Check `mongodb.image` in `values.yaml` (`docker.io/library/mongo:8.0`) |
| App pod `CrashLoopBackOff`, logs show `MongoServerSelectionError` / unhandled rejection | MongoDB not reachable yet. Restarts usually settle once MongoDB is up |
| `curl` → 404 from nginx | Missing `Host:` header / hosts entry, or no Ingress (`kubectl get ingress`) |
| `curl` → 503 | Backend pod not Ready |
| `kubectl apply` complains about `generateName` | Use `kubectl create -f` (not `apply`) for PipelineRuns |
| Flux GitRepository `auth` / `unable to clone` | `url` must be the `ssh://git@github.com/<user>/<repo>.git` form, secret must have `identity` + `known_hosts` |

---

# PART 2: LAB 2 (3.11.2026): Tekton CI + Flux CD (GitOps)

The CI pipeline builds and pushes the image, then **commits the new tag** into `helm/uploadapp/values-uploadapp.yaml` and pushes to GitHub. Flux watches the repo and deploys the HelmRelease. The pipeline never touches the cluster's deployments.

## 2.0 Start state

1. Make sure kubectl points at your lab cluster (`kubectl config current-context`).
2. If your cluster was reset since lab 1, redo 1.2, 1.3, 1.5, 1.7 and `kubectl apply -f cicd/upload-app-demo/10-pipeline-push.yaml`.
3. Update your clone: `cd ~/fri-uniza-onpk-cicd && git pull`.
4. Remove Demo 1's Helm release so Flux owns the release from scratch:

```bash
helm uninstall uploadapp --wait
```

## 2.1 Install Flux

Either with the CLI:

```bash
flux check --pre
flux install
flux check
```

or with the raw manifest (latest release):

```bash
kubectl apply -f https://github.com/fluxcd/flux2/releases/latest/download/install.yaml
kubectl -n flux-system wait --for=condition=ready pod --all --timeout=300s
```

## 2.2 Capacitor (Flux UI)

`cicd/upload-app-demo/20-fluxcd-capacitor.yaml` is itself a small GitOps example: an `OCIRepository` pointing at Capacitor's manifests, and a Flux `Kustomization` that applies them.

```bash
kubectl apply -f cicd/upload-app-demo/20-fluxcd-capacitor.yaml
kubectl -n flux-system wait kustomization/capacitor --for=condition=ready --timeout=300s
flux get kustomizations -A
# separate terminal, leave running:
kubectl -n flux-system port-forward svc/capacitor 9000:9000
# open http://localhost:9000
```

## 2.3 GitOps pipeline

`git-credentials` already contains `id_ed25519`, `identity` and `known_hosts` (1.7), and your deploy key has write access (1.6).

### 1. Read `cicd/upload-app-demo/21-pipeline-gitops.yaml`

Same first three tasks as Demo 1 (`fetch-source`, `add-build-info`, `buildah-build`), then no `helm upgrade`. Instead:

- `update-helm-values`: `yq` sets `image.repository` and `image.tag` in `helm/uploadapp/values-uploadapp.yaml`, then `helm lint`.
- `git-push`: commits the change and pushes it to `repo-branch` with the deploy key:

```yaml
    - name: git-push
      runAfter: [ "update-helm-values" ]
      taskSpec:
        steps:
          - name: git-push
            image: alpine/git:2.45.2
            script: |
              set -e
              cp -R "$(workspaces.ssh-directory.path)" /root/.ssh
              chmod 700 /root/.ssh
              chmod -R 400 /root/.ssh/*

              cd $(workspaces.source.path)
              git config --global --add safe.directory $(workspaces.source.path)
              git config --global user.name  "$(params.git-user-name)"
              git config --global user.email "$(params.git-user-email)"

              git checkout $(params.repo-branch)
              git add ./helm/uploadapp/values-uploadapp.yaml
              # no-op if the tag didn't change (rerun with the same image-tag)
              git diff --cached --quiet || git commit -m 'chore: update image.tag to version $(params.image-tag)'
              git push origin $(params.repo-branch)
```

`yq -i` rewrites the values file and may reformat the commented Slovak hint block. That's harmless.

### 2. The PipelineRun `cicd/upload-app-demo/22-pipeline-gitops-run.yaml`

```yaml
apiVersion: tekton.dev/v1beta1
kind: PipelineRun
metadata:
  generateName: upload-app-gitops-pipeline-run-
spec:
  serviceAccountName: pipeline-sa
  pipelineRef:
    name: upload-app-gitops-pipeline
  podTemplate:
    securityContext:
      fsGroup: 65532
  params:
    - name: repo-url
      value: git@github.com:<GITHUB_USER>/fri-uniza-onpk-cicd.git    # your fork (SSH url)
    - name: repo-branch
      value: "main"
    - name: image-name
      value: "ghcr.io/<GITHUB_USER>/fri-uniza-onpk-cicd"
    - name: image-tag
      value: "1.0.2"                                                 # bump on every run
    - name: git-user-email
      value: "<GITHUB_USER>@users.noreply.github.com"
  workspaces:
    - name: shared-data
      volumeClaimTemplate:
        spec:
          accessModes:
            - ReadWriteOnce
          resources:
            requests:
              storage: 1Gi
    - name: git-credentials
      secret:
        secretName: git-credentials
    - name: dockerconfig
      secret:
        secretName: docker-credentials
```

### 3. Run the pipeline

The pipeline pushes to the same branch you work on, so push your own changes first and pull afterwards.

```bash
git status                                   # clean, everything pushed
kubectl apply  -f cicd/upload-app-demo/21-pipeline-gitops.yaml
kubectl create -f cicd/upload-app-demo/22-pipeline-gitops-run.yaml
tkn pipelinerun logs -f --last
# afterwards, on GitHub: a new commit "chore: update image.tag to version 1.0.2"
git pull
```

## 2.4 Flux GitRepository + HelmRelease

### 1. Read `cicd/upload-app-demo/23-fluxcd-uploadapp.yaml`

```yaml
apiVersion: source.toolkit.fluxcd.io/v1
kind: GitRepository
metadata:
  name: uploadapp-git-repo
  namespace: default
spec:
  interval: 1m
  url: ssh://git@github.com/<GITHUB_USER>/fri-uniza-onpk-cicd.git   # ssh:// form, "/" not ":"
  ref:
    branch: main
  secretRef:
    name: git-credentials                                           # uses identity + known_hosts
---
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: uploadapp          # keep: the chart hardcodes DB_HOST=uploadapp-mongodb.<namespace>
  namespace: default
spec:
  interval: 1m
  timeout: 10m
  chart:
    spec:
      chart: helm/uploadapp
      reconcileStrategy: Revision
      valuesFiles:
        - ./helm/uploadapp/values.yaml
        - ./helm/uploadapp/values-uploadapp.yaml
      sourceRef:
        kind: GitRepository
        name: uploadapp-git-repo
```

`reconcileStrategy: Revision` makes Flux build a new chart version for every new Git commit, so a commit that only changes the values file still triggers an upgrade.

### 2. Apply it and watch Flux deploy

```bash
kubectl apply -f cicd/upload-app-demo/23-fluxcd-uploadapp.yaml
flux get sources git -n default            # -n default: flux commands default to flux-system
flux get helmreleases -n default
kubectl get pods -w                        # Ctrl-C when uploadapp and mongodb are Running
curl -s -H 'Host: uploadapp.mydomain.local' http://<INGRESS_ADDRESS>/info   # BuildVersion 1.0.2
```

Alternative to `git-credentials`: let Flux create its own secret with `flux create secret git uploadapp-git -n default --url=ssh://git@github.com/<GITHUB_USER>/fri-uniza-onpk-cicd.git --private-key-file=$HOME/lab-secrets/upload-app-deploy`, and set `secretRef.name: uploadapp-git`.

## 2.5 Close the loop: bump, rebuild, reconcile, roll back

### 1. Bump the tag and run CI

```bash
sed -i.bak 's/value: "1.0.2"/value: "1.0.3"/' cicd/upload-app-demo/22-pipeline-gitops-run.yaml && rm cicd/upload-app-demo/22-pipeline-gitops-run.yaml.bak   # or edit by hand
git commit -am "Bump image tag to 1.0.3" && git push
kubectl create -f cicd/upload-app-demo/22-pipeline-gitops-run.yaml
tkn pipelinerun logs -f --last
```

### 2. Watch Flux deploy it

The interval is 1 minute. To force it:

```bash
flux reconcile source git uploadapp-git-repo -n default
flux get helmreleases -n default --watch          # Ctrl-C when Ready with the new revision
kubectl get pods -w
curl -s -H 'Host: uploadapp.mydomain.local' http://<INGRESS_ADDRESS>/info   # BuildVersion 1.0.3
helm history uploadapp                 # Flux-driven revisions
```

### 3. Roll back the GitOps way: revert the bot's commit

```bash
cd ~/fri-uniza-onpk-cicd
git pull
git log --oneline -3                   # top: "chore: update image.tag to version 1.0.3"
git revert --no-edit HEAD
git push
flux reconcile source git uploadapp-git-repo -n default
flux get helmreleases -n default --watch
curl -s -H 'Host: uploadapp.mydomain.local' http://<INGRESS_ADDRESS>/info   # back to 1.0.2
```

### 4. Discuss

- Git is the source of truth. Image 1.0.3 still exists in the registry, but nothing references it.
- `flux suspend helmrelease uploadapp -n default` / `flux resume helmrelease uploadapp -n default`: change something by hand while suspended, then resume and watch Flux undo the drift.

## 2.6 Optional: Tekton Triggers

Run a pipeline automatically from a GitHub pull-request event.

### 1. Install Triggers and the interceptors (v0.37.2)

```bash
kubectl apply -f https://infra.tekton.dev/tekton-releases/triggers/previous/v0.37.2/release.yaml
kubectl apply -f https://infra.tekton.dev/tekton-releases/triggers/previous/v0.37.2/interceptors.yaml
kubectl wait -n tekton-pipelines --for=condition=ready pod -l app.kubernetes.io/part-of=tekton-triggers --timeout=300s
```

### 2. Apply the secret and RBAC from the repo

`github-secret.yml` holds the webhook secret (change the token if you like, and in `curl.sh` too). `rbac.yml` binds `tekton-triggers-example-sa` to the ClusterRoles the Triggers release creates.

```bash
kubectl apply -f cicd/github-trigger/github-secret.yml
kubectl apply -f cicd/github-trigger/rbac.yml
```

### 3. The EventListener `cicd/github-trigger/github-eventlistener-interceptor.yml`

- `EventListener github-listener`: accepts GitHub `pull_request` events, checks the HMAC signature against `github-secret` (`github` interceptor) and lets only `opened` / `synchronize` / `reopened` through (`cel` interceptor).
- `TriggerBinding github-pr-binding`: takes `gitrevision` from `body.pull_request.head.sha`.
- `TriggerTemplate github-template`: creates a PipelineRun of the Demo 1 pipeline `clone-build-push-deploy` for that commit, with the commit sha as image tag.

The Demo 1 pipeline deploys with plain Helm, while Flux also manages `uploadapp` in lab 2. Run this either before 2.4 or with the HelmRelease suspended (`flux suspend helmrelease uploadapp -n default`), so the two don't fight.

### 4. Fire a fake GitHub event

Port-forward the listener to local port 8090. The sha must exist in your GitHub repo (push first).

```bash
kubectl apply -f cicd/github-trigger/github-eventlistener-interceptor.yml
kubectl get eventlistener github-listener        # wait for ADDRESS / Ready
kubectl port-forward svc/el-github-listener 8090:8080 &

./cicd/github-trigger/curl.sh                    # sends a signed pull_request event for HEAD
tkn pipelinerun list                             # clone-build-push-deploy-trigger-xxxxx
kill %1                                          # stop the background port-forward
```

Real GitHub webhooks can't reach a cluster without a public address. You would need a tunnel (smee.io client, ngrok, cloudflared) pointing at the port-forward. That's out of scope.

## 2.7 Optional: Flagger

Flagger (flagger.app, part of the Flux family) automates canary and blue-green rollouts. A `Canary` object wraps the Deployment, shifts traffic step by step through ingress-nginx, and rolls back automatically when metrics fail. It's the natural next step after 2.5: instead of switching straight to 1.0.3, Flagger promotes it gradually. It needs Prometheus and the ingress-nginx metrics. See the "NGINX Canary Deployments" tutorial in the Flagger docs. Not part of this lab.

---

# CLEANUP (end of lab 2)

Remove the lab resources. Leave the cluster itself alone.

```bash
# app and pipelines
kubectl delete -f cicd/upload-app-demo/23-fluxcd-uploadapp.yaml --ignore-not-found
helm uninstall uploadapp --ignore-not-found
kubectl delete pipelineruns --all ; kubectl delete taskruns --all

# optional: Triggers objects
kubectl delete -f cicd/github-trigger/github-eventlistener-interceptor.yml --ignore-not-found

# hosts entry, if you added one (Windows: edit the hosts file as Administrator)
sudo sed -i.bak '/uploadapp.mydomain.local/d' /etc/hosts

# credentials
kubectl delete secret docker-credentials ghcr-pull git-credentials --ignore-not-found
rm -rf ~/lab-secrets
# GitHub: your repo -> Settings -> Deploy keys -> delete the lab key
# GitHub: Settings -> Developer settings -> Personal access tokens (classic) -> delete the lab token
# optional: your profile -> Packages -> fri-uniza-onpk-cicd -> Package settings -> Delete this package
```
