# DevOps GitOps Demo (Kubernetes + Terraform + ArgoCD + GitHub Actions + Trivy + Prometheus/Grafana)

Ek din mein hands-on karne layak end-to-end DevOps project. Sab kuch local machine par chalta hai (free).

## Architecture

```
git push -> GitHub Actions (test -> build -> Trivy scan -> push GHCR -> helm values tag update)
                                                        |
                                                        v
                         ArgoCD (Git watch karta hai) -> Kubernetes (kind) -> demo-app
                                                        |
                                    Prometheus + Grafana <- /metrics
Terraform: kind cluster + ArgoCD + kube-prometheus-stack banata hai
```

## Prerequisites
Docker, Terraform (>=1.5), kubectl, git, ek GitHub account.

## Steps (total ~5-6 ghante)

### 1. Repo setup (20 min)
1. GitHub par naya repo banao: `devops-gitops-demo` (**public** rakho).
2. Is folder ko push karo:
   ```bash
   ./scripts/configure.sh <apna-github-username>
   git init && git add . && git commit -m "initial commit"
   git branch -M main
   git remote add origin https://github.com/<username>/devops-gitops-demo.git
   git push -u origin main
   ```
3. Repo Settings -> Actions -> General -> Workflow permissions -> **Read and write** select karo.

### 2. CI chalao (20 min)
- Actions tab mein `ci` workflow dekho: test -> Trivy scan -> image push -> `values.yaml` mein tag auto-update.
- Ho jaye to GitHub profile -> Packages -> `devops-gitops-demo` -> Package settings -> visibility **Public** karo (warna kind image pull nahi kar payega).
- `git pull` karo taaki CI ka tag-update commit local mein aa jaye.

### 3. Terraform se cluster (30-40 min)
```bash
cd terraform
terraform init
terraform apply -auto-approve
kubectl get nodes
```
Isse kind cluster + ArgoCD + Prometheus/Grafana install ho jayenge.

### 4. App ArgoCD se deploy karo (15 min)
```bash
kubectl apply -f argocd/application.yaml
kubectl get pods -n demo -w
curl http://localhost:8080/
```

### 5. ArgoCD UI
```bash
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d; echo
kubectl port-forward svc/argocd-server -n argocd 8081:443
```
Browser: https://localhost:8081 (user: `admin`).

### 6. Grafana / Prometheus (30 min)
```bash
kubectl port-forward svc/monitoring-grafana -n monitoring 3000:80
```
Browser: http://localhost:3000 (user `admin`, password `prom-operator`).
Explore -> Prometheus mein query: `rate(app_requests_total[1m])`. Traffic ke liye `./scripts/loadtest.sh` chalao.
Dashboards mein "Kubernetes / Compute Resources / Namespace (Pods)" mein `demo` namespace dekho.

### 7. GitOps ka asli demo (1 ghanta)
- **Auto-deploy:** `app/app.py` mein message badlo, push karo -> CI -> naya tag -> ArgoCD auto-sync -> `curl localhost:8080`.
- **Self-heal:** `kubectl scale deploy demo-app -n demo --replicas=5` -> ArgoCD wapas 2 kar dega.
- **Rollback:** `git revert <commit>` -> push -> ArgoCD purana version laa dega.
- **Alert:** `kubectl scale deploy demo-app -n demo --replicas=0` (ArgoCD self-heal band karne ke liye pehle Application mein `selfHeal: false` kar do) -> Prometheus Alerts mein `DemoAppDown` firing dikhega.
- **Security gate:** Dockerfile mein purani base image (jaise `python:3.8`) daalo -> Trivy CI fail karega. Screenshot lo.

### 8. Cleanup
```bash
cd terraform && terraform destroy -auto-approve
```

## Troubleshooting
- `ImagePullBackOff`: GHCR package public nahi hai, ya `values.yaml` mein username galat hai.
- ArgoCD Application `OutOfSync` aur CRD error: monitoring install poora hone do (`kubectl get pods -n monitoring`), phir retry.
- Port 8080 busy: `terraform/main.tf` mein `host_port` badlo.
- Terraform apply ke time helm timeout: dobara `terraform apply` chalao.

## Resume bullets (apne actual results ke hisaab se edit karna)
- Built GitOps CI/CD pipeline using GitHub Actions and ArgoCD deploying a containerized Flask service to Kubernetes via Helm.
- Provisioned cluster, ArgoCD and monitoring stack as code with Terraform.
- Integrated Trivy image scanning as a CI quality gate and hardened pods (non-root, read-only filesystem, dropped capabilities).
- Implemented Prometheus metrics, ServiceMonitor and alert rules with Grafana dashboards.

## Interview mein bolne ke points
- Push vs pull deployment (CI push karta hai image, ArgoCD pull karta hai state).
- Git ek single source of truth hai, rollback = `git revert`.
- Self-heal kya hota hai aur drift kaise detect hota hai.
- Shift-left security: scan pipeline mein, deploy se pehle.
