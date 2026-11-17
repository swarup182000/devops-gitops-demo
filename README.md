# GitOps CI/CD Pipeline on Kubernetes

A small but complete DevOps project: a containerized Flask service that is tested, security-scanned, built and deployed automatically with a GitOps workflow. The cluster, ArgoCD and the monitoring stack are all provisioned with Terraform.

I built and ran this end to end on an AWS EC2 instance (Ubuntu, `t3.large`, 30 GB disk) using a local `kind` cluster.

## What it does

Pushing a change to `app/` triggers the whole chain with no manual steps:

1. GitHub Actions runs the unit tests.
2. The Docker image is built and scanned with Trivy. The pipeline fails on CRITICAL vulnerabilities.
3. The image is pushed to GitHub Container Registry, tagged with the commit SHA.
4. The pipeline writes the new tag into `helm/demo-app/values.yaml` and commits it.
5. ArgoCD detects the change in Git and rolls the new version out to the cluster.
6. Prometheus scrapes the app's `/metrics` endpoint and Grafana visualises it.

## Architecture

```
developer
   |  git push
   v
GitHub repo ---> GitHub Actions
                 test -> build -> Trivy scan -> push image (GHCR) -> bump tag in values.yaml
   |
   |  (ArgoCD watches the repo and pulls changes)
   v
ArgoCD ---> Kubernetes (kind) ---> demo-app (2 replicas)
                                        |
                                        | /metrics
                                        v
                              Prometheus ---> Grafana + alert rules

Terraform provisions: kind cluster, ArgoCD, kube-prometheus-stack
```

CI never talks to the cluster. The cluster pulls its desired state from Git, which is the core idea of GitOps.

## Tech stack

| Area | Tools |
|------|-------|
| App | Python, Flask, Gunicorn, prometheus-client, pytest |
| Containers | Docker, GitHub Container Registry |
| CI | GitHub Actions |
| Security | Trivy image scanning, non-root container, read-only root filesystem, dropped Linux capabilities |
| Infrastructure as code | Terraform (kind provider, Helm provider) |
| Orchestration | Kubernetes (kind), Helm |
| CD / GitOps | ArgoCD (automated sync, prune, self-heal) |
| Observability | Prometheus, Grafana, ServiceMonitor, PrometheusRule |

## Repository layout

```
app/                    Flask service, tests, Dockerfile
helm/demo-app/          Helm chart (Deployment, Service, ServiceMonitor, PrometheusRule)
argocd/                 ArgoCD Application manifest
terraform/              kind cluster + ArgoCD + monitoring stack
scripts/                helper scripts (load test, configuration)
.github/workflows/      CI pipeline
```


## Running it yourself

**Requirements:** Docker, Terraform 1.5+, kubectl, git, a GitHub account. About 8 GB of RAM and 20 GB of free disk.

1. Fork this repository and replace `swarup182000` with your GitHub username in `helm/demo-app/values.yaml` and `argocd/application.yaml`.
2. In the repo settings, give Actions **read and write** permissions, then push a change to `app/` so CI builds the first image.
3. Set the published container package to **public** so the cluster can pull it without credentials.
4. Create the cluster and platform components:
   ```bash
   cd terraform
   terraform init
   terraform apply -auto-approve
   export KUBECONFIG=$(pwd)/devops-demo-config
   ```
5. Deploy the application through ArgoCD:
   ```bash
   kubectl apply -f ../argocd/application.yaml
   kubectl get pods -n demo
   curl http://localhost:8080/
   ```
6. Open the dashboards:
   ```bash
   # ArgoCD (user: admin)
   kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
   kubectl port-forward svc/argocd-server -n argocd 8081:443

   # Grafana (user: admin)
   kubectl get secret monitoring-grafana -n monitoring -o jsonpath="{.data.admin-password}" | base64 -d
   kubectl port-forward svc/monitoring-grafana -n monitoring 3000:80
   ```
7. Generate traffic with `./scripts/loadtest.sh` and query `rate(app_requests_total[1m])` in Grafana Explore.

To tear everything down: `cd terraform && terraform destroy -auto-approve`.

## Things to try

- **Auto-deploy:** change the message in `app/app.py`, push, and watch CI and ArgoCD roll it out.
- **Self-heal:** run `kubectl scale deploy demo-app -n demo --replicas=5` and watch ArgoCD bring it back to 2.
- **Rollback:** `git revert` the last deployment commit and push.
- **Alerting:** scale the deployment to 0 (with self-heal disabled) to fire the `DemoAppDown` alert.
- **Security gate:** switch the Dockerfile to an old base image and see whether Trivy blocks the build.

## Problems I ran into

These were the most useful part of the project, so I am keeping them here.

- **Disk full on the default 8 GB volume.** Docker images, the kind nodes and the Prometheus stack filled the disk. The first `terraform apply` failed with confusing `connection reset` and `no space left on device` errors. I resized the EBS volume to 30 GB, grew the partition and filesystem, and rebuilt the cluster.
- **Terraform state out of sync with reality.** After the failed run, Terraform's state referenced a kind cluster that no longer existed, and half-created containers blocked a fresh apply ("node(s) already exist"). I removed the leftover containers and the stale state file before re-applying.
- **Pinned GitHub Action no longer resolvable.** The pinned `aquasecurity/trivy-action` version could not be found, which broke the pipeline. I replaced it with running the official Trivy Docker image directly in the workflow.
- **Race condition in the CI commit step.** The job that writes the new image tag back to Git was rejected when another commit landed on `main` in the meantime. Adding `git pull --rebase` before `git push` fixed it.
- **Tooling gotchas.** Learned the hard way that `kubectl`/`terraform` need the right `KUBECONFIG`, that tmux helps with long applies over SSH, and that SSH tunnels are a safer way to reach dashboards than opening ports in the security group.

## What I would improve next

- Replace `kind` with a managed cluster (EKS) provisioned by Terraform, with remote state in S3.
- Add an ingress controller and TLS instead of NodePort and port-forwarding.
- Manage secrets with External Secrets or Vault.
- Add Kyverno or OPA policies and pin the Trivy version.
- Ship a prebuilt Grafana dashboard as code.
