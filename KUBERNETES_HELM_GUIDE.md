# Kubernetes & Helm Learning Guide

> **Who is this for?**
> This guide is written for frontend and backend developers who know how to build apps and use Docker,
> but have never touched Kubernetes or Helm before. No ops background required.
> Every command is explained. Every concept is defined before it is used.

---

## Table of Contents

1. [What Problem Does Kubernetes Solve?](#what-problem-does-kubernetes-solve)
2. [Core Concepts — Plain English](#core-concepts--plain-english)
3. [Prerequisites — Install Everything First](#prerequisites--install-everything-first)
4. [Verify Your Setup](#verify-your-setup)
5. [Project Structure Added](#project-structure-added)
6. [Hands-On Lab 1 — Run the App Locally with Docker](#hands-on-lab-1--run-the-app-locally-with-docker)
7. [Hands-On Lab 2 — Deploy with Raw Kubernetes Manifests](#hands-on-lab-2--deploy-with-raw-kubernetes-manifests)
8. [Hands-On Lab 3 — Deploy with Helm](#hands-on-lab-3--deploy-with-helm)
9. [Hands-On Lab 4 — Simulate Real Scenarios](#hands-on-lab-4--simulate-real-scenarios)
10. [Part 3 — Environment-specific Values](#part-3--environment-specific-values)
11. [Part 4 — Jenkins Integration](#part-4--jenkins-integration)
12. [Concepts Summary](#concepts-summary)

---

## What Problem Does Kubernetes Solve?

As a developer you have built and run containers like this:

```bash
docker run -p 3000:80 react-app:latest
```

That works on your laptop. But in production you need answers to:

| Question | Without Kubernetes | With Kubernetes |
|----------|-------------------|-----------------|
| What if the container crashes? | Manually restart it | Automatically restarted |
| How do I run 5 copies for traffic? | Run 5 docker run commands | Set `replicas: 5` |
| How do I update with zero downtime? | Stop → start (gap in service) | Rolling update |
| How do I route traffic to healthy copies? | You handle it yourself | Service + health probes |
| How do I scale automatically under load? | Not easy | HPA does it for you |

**Kubernetes** is a system that manages containers at scale — it keeps them running, healthy, and reachable.

**Helm** is a package manager for Kubernetes. Think of it like `npm` but for Kubernetes YAML files. Instead of copying YAML between projects, you write a chart once and reuse it across environments by changing values.

---

## Core Concepts — Plain English

Read this section fully before running any commands. It will make everything else click.

### Cluster
A set of machines (nodes) that Kubernetes manages. Minikube gives you a single-machine cluster on your laptop.

### Node
A single machine (VM or physical) inside the cluster. Has CPU, memory, and runs containers.

### Pod
The smallest deployable unit in Kubernetes. A Pod wraps one or more containers that share the same network and storage. You never manage containers directly — you manage Pods.

```
Node
└── Pod
    └── Container (your react-app running inside nginx)
```

### Deployment
A controller that says "I want 2 copies of this Pod always running." If one crashes, Kubernetes creates a new one automatically. If you push a new image, a Deployment does a rolling update with zero downtime.

### ReplicaSet
What a Deployment creates internally to track how many Pod copies exist. You rarely interact with it directly.

### Service
Pods have their own IPs that change every time a Pod restarts. A Service gives you a **stable IP and DNS name** that always points to the healthy Pods.

```
You → Service (stable: react-app-service:80)
           ↓ load balances to ↓
      Pod-1    Pod-2    Pod-3
```

### Ingress
A Service only works inside the cluster. An Ingress exposes HTTP/HTTPS routes from the internet (or your laptop) into the cluster. Think of it as a smart reverse-proxy.

### ConfigMap
Stores configuration as key-value pairs (like `.env` files) inside Kubernetes. Injected into Pods as environment variables or files. Keeps config out of your Docker image.

### Namespace
A virtual partition inside the cluster. Lets you group resources and avoid name collisions. Like separate folders for dev/staging/prod inside one cluster.

### HPA (HorizontalPodAutoscaler)
Watches CPU/memory metrics and automatically adds or removes Pod replicas. Your app scales up under load and scales down when quiet — no manual intervention.

### Helm Chart
A folder of Kubernetes YAML templates with placeholders. Placeholders are filled in from a `values.yaml` file. One chart → deploy to dev, staging, prod by just changing the values.

---

## Prerequisites — Install Everything First

> Complete **all steps** in order before running any Kubernetes commands.
> If you skip a tool, later steps will fail.

---

### 1. Docker Desktop

Docker is required — Kubernetes runs your app as a Docker image.

**Windows / macOS:**
Download and install from https://www.docker.com/products/docker-desktop

After install, open Docker Desktop and wait until it shows **"Engine running"** in the bottom-left.

Verify:
```bash
docker --version
# Expected: Docker version 24.x or higher
```

---

### 2. Minikube — Local Kubernetes Cluster

Minikube runs a real single-node Kubernetes cluster on your laptop inside a VM or Docker container. It is the standard learning environment.

**Windows (Winget):**
```powershell
winget install Kubernetes.minikube
```

**Windows (Manual):** Download `minikube-installer.exe` from https://minikube.sigs.k8s.io/docs/start

**macOS (Homebrew):**
```bash
brew install minikube
```

**Linux:**
```bash
curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
sudo install minikube-linux-amd64 /usr/local/bin/minikube
```

Verify:
```bash
minikube version
# Expected: minikube version: v1.32.x or higher
```

---

### 3. kubectl — Kubernetes Command-Line Tool

`kubectl` is how you talk to any Kubernetes cluster (Minikube, AWS EKS, GKE, etc.).

**Windows (Winget):**
```powershell
winget install Kubernetes.kubectl
```

**macOS (Homebrew):**
```bash
brew install kubectl
```

**Linux:**
```bash
curl -LO "https://dl.k8s.io/release/$(curl -sL https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -m 0755 kubectl /usr/local/bin/kubectl
```

Verify:
```bash
kubectl version --client
# Expected: Client Version: v1.28.x or higher
```

---

### 4. Helm 3 — Kubernetes Package Manager

**Windows (Winget):**
```powershell
winget install Helm.Helm
```

**macOS (Homebrew):**
```bash
brew install helm
```

**Linux / Script:**
```bash
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
```

Verify:
```bash
helm version
# Expected: version.BuildInfo{Version:"v3.14.x", ...}
```

---

### 5. VS Code Extensions (Optional but Recommended)

Install these from the VS Code Extensions panel (`Ctrl+Shift+X`):

| Extension | Why |
|-----------|-----|
| **Kubernetes** (ms-kubernetes-tools) | Browse cluster resources, view pod logs in VS Code |
| **YAML** (redhat.vscode-yaml) | Syntax validation for all `.yaml` files |
| **Helm Intellisense** | Autocomplete inside Helm templates |

---

## Verify Your Setup

Run these commands one by one. All must succeed before continuing.

```bash
# 1. Docker is running
docker ps

# 2. Minikube can start
minikube start
# First run downloads a VM image — can take 3-5 minutes

# 3. kubectl connects to Minikube
kubectl cluster-info
# Expected: Kubernetes control plane is running at https://127.0.0.1:...

# 4. Helm is working
helm version

# 5. (Optional) Open the Kubernetes dashboard in browser
minikube dashboard
```

> If `minikube start` fails, make sure Docker Desktop is running first.
> Minikube uses Docker as its driver by default on Windows/macOS.

---

## Project Structure Added

```
k8s/                          ← Raw Kubernetes manifests (learn the basics)
├── namespace.yaml            ← Logical partition for this app
├── configmap.yaml            ← Non-sensitive config as key-value pairs
├── deployment.yaml           ← Manages pod replicas + rolling updates
├── service.yaml              ← Stable network endpoint for pods
├── ingress.yaml              ← External HTTP routing into the cluster
└── hpa.yaml                  ← Auto-scales pods on CPU/memory pressure

helm/
└── react-app/                ← Helm chart (reusable, parameterized k8s)
    ├── Chart.yaml            ← Chart metadata (name, version)
    ├── values.yaml           ← Default values (override per environment)
    └── templates/
        ├── _helpers.tpl      ← Reusable template functions
        ├── configmap.yaml    ← Templated ConfigMap
        ├── deployment.yaml   ← Templated Deployment
        ├── service.yaml      ← Templated Service
        ├── ingress.yaml      ← Templated Ingress (conditional)
        ├── hpa.yaml          ← Templated HPA (conditional)
        └── NOTES.txt         ← Post-install instructions
```

---

## Hands-On Lab 1 — Run the App Locally with Docker

> **Goal:** Confirm the Docker image builds and runs correctly before touching Kubernetes.
> If this doesn't work, Kubernetes won't work either.

```bash
# Step 1 — Build the image
docker build -t react-app:latest .

# Step 2 — Run it
docker run -d -p 3000:80 --name react-test react-app:latest

# Step 3 — Open in browser
# Navigate to http://localhost:3000
# You should see the React app.

# Step 4 — Check the container is running
docker ps

# Step 5 — View logs (useful habit before going to k8s)
docker logs react-test

# Step 6 — Clean up
docker stop react-test
docker rm react-test
```

**What you learned:** The image works. Port 80 inside the container → port 3000 on your machine. This same image is what Kubernetes will run.

---

## Hands-On Lab 2 — Deploy with Raw Kubernetes Manifests

> **Goal:** Understand every Kubernetes object by applying them one at a time and observing what changes.
> Raw manifests are the foundation — learn these before Helm.

### Step 1 — Start Minikube

```bash
minikube start
```

Wait for the output to say `Done! kubectl is now configured to use "minikube"`.

### Step 2 — Point Docker at Minikube's internal registry

When you build an image on your laptop, Minikube's cluster cannot see it — they use separate Docker daemons. This command makes them share one daemon.

```bash
# Windows PowerShell
minikube docker-env | Invoke-Expression

# macOS / Linux
eval $(minikube docker-env)
```

> **Important:** You must run this in every new terminal session. It only affects the current terminal.

### Step 3 — Rebuild the image inside Minikube's daemon

```bash
docker build -t react-app:latest .
```

Verify the image is visible to Minikube:
```bash
minikube image ls | grep react-app
# Should print: docker.io/library/react-app:latest
```

### Step 4 — Create the Namespace

A Namespace is a logical folder inside the cluster. All our resources will live in `react-app`.

```bash
kubectl apply -f k8s/namespace.yaml
```

Verify:
```bash
kubectl get namespaces
# You should see "react-app" in the list
```

### Step 5 — Apply the ConfigMap

ConfigMaps store environment configuration outside the image.

```bash
kubectl apply -f k8s/configmap.yaml
```

Inspect what was created:
```bash
kubectl get configmap -n react-app
kubectl describe configmap react-app-config -n react-app
# You will see APP_ENV, APP_NAME, NGINX_PORT listed as data
```

### Step 6 — Create the Deployment

The Deployment tells Kubernetes: "run 2 copies of react-app:latest, keep them healthy."

```bash
kubectl apply -f k8s/deployment.yaml
```

Watch the Pods start up in real time:
```bash
kubectl get pods -n react-app -w
# Press Ctrl+C when both pods show STATUS: Running
```

Inspect a Pod:
```bash
# Copy a pod name from the output above, e.g. react-app-7d4f9b-xkp2v
kubectl describe pod <pod-name> -n react-app
# Look at the Events section at the bottom — this is where errors appear
```

Check the environment variables were injected from the ConfigMap:
```bash
kubectl exec -it <pod-name> -n react-app -- env | grep APP
# Should print APP_ENV=production and APP_NAME=basic-react-app
```

### Step 7 — Create the Service

The Service gives the Pods a stable network address inside the cluster.

```bash
kubectl apply -f k8s/service.yaml
```

```bash
kubectl get service -n react-app
# Note the NodePort value (30080) under PORT(S) column
```

### Step 8 — Open the App

```bash
minikube service react-app-service -n react-app
# Minikube opens the app in your default browser automatically
```

Or get the URL manually:
```bash
minikube service react-app-service -n react-app --url
# Paste this URL into your browser
```

### Step 9 — Apply Ingress (Optional — requires Ingress addon)

```bash
# Enable the nginx ingress controller on Minikube
minikube addons enable ingress

# Wait ~60 seconds, then apply
kubectl apply -f k8s/ingress.yaml
```

Add this line to your hosts file so the domain resolves locally:

- **Windows:** Open `C:\Windows\System32\drivers\etc\hosts` as Administrator
- **macOS/Linux:** `sudo nano /etc/hosts`

Add:
```
127.0.0.1  react-app.local
```

Get Minikube's IP and tunnel:
```bash
minikube tunnel
# Keep this running in a separate terminal
```

Now open `http://react-app.local` in your browser.

### Step 10 — Apply HPA

```bash
# Enable metrics-server (required for HPA to work)
minikube addons enable metrics-server

kubectl apply -f k8s/hpa.yaml
```

Watch it:
```bash
kubectl get hpa -n react-app -w
# Initially shows <unknown> for CPU — waits ~60s for first metrics
```

### Step 11 — Explore Failure Recovery

This is one of the most important things to understand about Kubernetes.

```bash
# Get a pod name
kubectl get pods -n react-app

# Delete one pod (simulates a crash)
kubectl delete pod <pod-name> -n react-app

# Watch what happens
kubectl get pods -n react-app -w
# Kubernetes immediately creates a replacement pod — your Deployment's replicas: 2 is enforced
```

### Step 12 — Clean Up Lab 2

```bash
kubectl delete -f k8s/
# Removes all resources you created
```

---

## Hands-On Lab 3 — Deploy with Helm

> **Goal:** Deploy the same app using the Helm chart. See how Helm makes multi-environment deployments manageable.
> You need Minikube running and the image built from Lab 2 before starting this lab.

### What is different about Helm?

| Raw Manifests | Helm Chart |
|--------------|------------|
| Copy-paste YAML per environment | One chart, different `values.yaml` per env |
| No rollback history | `helm history` shows every release |
| Manual `kubectl apply` each file | One `helm upgrade --install` command |
| No concept of a "release" | Named releases, easy to manage multiple installs |

### Step 1 — Lint the Chart

Linting checks your templates for syntax errors without connecting to a cluster.

```bash
helm lint ./helm/react-app
```

Expected output: `1 chart(s) linted, 0 chart(s) failed`

### Step 2 — Render Templates Locally

This command renders all templates to plain YAML without applying anything. Use it to see what Kubernetes will actually receive.

```bash
helm template react-app-release ./helm/react-app
```

Try overriding a value and see the rendered output change:
```bash
helm template react-app-release ./helm/react-app --set replicaCount=5
# In the Deployment output, look for replicas: 5
```

### Step 3 — Dry Run Against the Cluster

A dry run validates the rendered YAML against the cluster's API (checks resource types, required fields) without creating anything.

```bash
helm install react-app-release ./helm/react-app \
  --namespace react-app \
  --create-namespace \
  --dry-run --debug
```

Read the output — it shows every resource that would be created plus the NOTES.txt message.

### Step 4 — Install the Chart

```bash
helm install react-app-release ./helm/react-app \
  --namespace react-app \
  --create-namespace
```

Helm prints the NOTES.txt after install — follow the instructions to open the app.

Verify the release:
```bash
helm list -n react-app
# Shows: NAME, NAMESPACE, REVISION, STATUS, CHART, APP VERSION
```

Verify the Kubernetes resources were created:
```bash
kubectl get all -n react-app
```

### Step 5 — Upgrade: Scale Up

Change a value and upgrade — no YAML editing required.

```bash
helm upgrade react-app-release ./helm/react-app \
  --namespace react-app \
  --set replicaCount=4
```

```bash
kubectl get pods -n react-app
# Should now show 4 running pods
```

### Step 6 — Upgrade: Use a New Image Tag

Simulates deploying a new version of your app (as Jenkins would do in CI/CD).

```bash
# Tag the current image as version 2
docker tag react-app:latest react-app:2

helm upgrade react-app-release ./helm/react-app \
  --namespace react-app \
  --set image.tag=2
```

Watch the rolling update:
```bash
kubectl rollout status deployment/react-app-release-react-app -n react-app
```

### Step 7 — View Revision History

Every `helm upgrade` creates a new revision. This is Helm's built-in audit trail.

```bash
helm history react-app-release -n react-app
```

Output shows each revision, when it was deployed, and its status.

### Step 8 — Rollback to Previous Version

```bash
# Roll back to revision 1
helm rollback react-app-release 1 -n react-app

# Confirm
helm history react-app-release -n react-app
# Revision 3 will show status: deployed and description: Rollback to 1
```

### Step 9 — Uninstall

```bash
helm uninstall react-app-release -n react-app
# Removes all Kubernetes resources created by this chart
```

---

## Hands-On Lab 4 — Simulate Real Scenarios

> These exercises build on Labs 2 and 3. Re-install the chart before starting.

```bash
helm install react-app-release ./helm/react-app \
  --namespace react-app --create-namespace
```

### Scenario A — A Pod is Crashing

```bash
# Watch pods
kubectl get pods -n react-app -w

# In a second terminal, force-delete a pod
kubectl delete pod <pod-name> -n react-app --force

# Observe: Kubernetes replaces it within seconds
```

### Scenario B — Inspect Why a Pod Won't Start

If a Pod is stuck in `Pending` or `CrashLoopBackOff`:

```bash
# Step 1: See the error summary
kubectl get pods -n react-app

# Step 2: Get the detailed event log
kubectl describe pod <pod-name> -n react-app
# Read the "Events:" section at the bottom

# Step 3: See the container's stdout/stderr
kubectl logs <pod-name> -n react-app

# Step 4: If the container keeps crashing, see the previous run's logs
kubectl logs <pod-name> -n react-app --previous
```

Common causes:
- `ImagePullBackOff` — image name or tag is wrong, or not visible to Minikube
- `CrashLoopBackOff` — the app inside the container is crashing (check `kubectl logs`)
- `Pending` — not enough CPU/memory on the node (check `kubectl describe pod`)

### Scenario C — Zero-Downtime Deploy (Watch It Live)

```bash
# Terminal 1: Watch pods
kubectl get pods -n react-app -w

# Terminal 2: Trigger a rolling update
helm upgrade react-app-release ./helm/react-app \
  --namespace react-app \
  --set image.tag=latest

# In Terminal 1, observe:
# - New pods start (ContainerCreating → Running)
# - Old pods terminate ONLY after new ones are healthy
# Zero traffic interruption
```

### Scenario D — Exec Into a Running Container

Like SSH-ing into a server, but for a Pod:

```bash
kubectl exec -it <pod-name> -n react-app -- /bin/sh

# Now you are inside the container:
ls /usr/share/nginx/html   # see your built React files
env                        # see environment variables from ConfigMap
cat /etc/nginx/conf.d/default.conf   # see nginx config
exit
```

### Scenario E — Port-Forward Without a Service

Useful for debugging a single Pod directly, bypassing Service and Ingress:

```bash
kubectl port-forward pod/<pod-name> 8080:80 -n react-app
# Open http://localhost:8080 — you are talking directly to that one Pod
```

---

## Part 3 — Environment-specific Values

Override values per environment without touching the chart:

```bash
# Production: more replicas, real image, LoadBalancer
helm upgrade --install react-app-release ./helm/react-app \
  --set image.repository=your-dockerhub/react-app \
  --set image.tag=2.0.0 \
  --set replicaCount=5 \
  --set service.type=LoadBalancer \
  --set ingress.host=myapp.com \
  --namespace prod \
  --create-namespace
```

Or use a separate values file:
```bash
helm upgrade --install react-app-release ./helm/react-app \
  -f helm/react-app/values.yaml \
  -f helm/react-app/values.prod.yaml \   ← overrides win
  --namespace prod
```

---

## Part 4 — Jenkins Integration

Two Boolean parameters are added to the Jenkinsfile:

| Parameter | Effect |
|-----------|--------|
| `DEPLOY_TO_K8S` | Applies raw `k8s/` manifests after Docker build |
| `DEPLOY_WITH_HELM` | Runs Helm lint → dry-run → deploy stages |

To enable in Jenkins:
1. Open the job → **Configure**
2. Check **This project is parameterized**
3. Add **Boolean Parameter** → name: `DEPLOY_TO_K8S`, default: `false`
4. Add **Boolean Parameter** → name: `DEPLOY_WITH_HELM`, default: `false`

---

## Concepts Summary

```
Docker Image → pushed to registry
      ↓
Kubernetes Deployment → manages ReplicaSet → manages Pods
      ↓                                            ↓
  Service (stable IP) ←──────────── routes traffic to Pods
      ↓
  Ingress (external routing)
      ↓
  HPA (auto-scale pods)

Helm = template engine + release manager on top of all of the above
```
