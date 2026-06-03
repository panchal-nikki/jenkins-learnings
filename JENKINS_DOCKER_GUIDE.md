# CI/CD with Jenkins + Docker: Complete Guide

> **Target audience:** Frontend developers (5+ years) who are comfortable with React, npm, and modern tooling — but new to Jenkins and Docker-based CI/CD pipelines.

---

## Table of Contents

1. [The Big Picture — What & Why](#1-the-big-picture--what--why)
2. [Architecture Overview](#2-architecture-overview)
3. [Project Structure Explained](#3-project-structure-explained)
4. [Docker Deep Dive](#4-docker-deep-dive)
   - [What is Docker and why does a frontend dev care?](#what-is-docker-and-why-does-a-frontend-dev-care)
   - [Dockerfile (the React App image)](#dockerfile-the-react-app-image)
   - [Dockerfile.jenkins (the custom Jenkins image)](#dockerfilejenkins-the-custom-jenkins-image)
   - [docker-compose.yml (running Jenkins)](#docker-composeyml-running-jenkins)
   - [docker-compose.dev.yml (local dev preview)](#docker-composedevyml-local-dev-preview)
5. [Nginx Deep Dive](#5-nginx-deep-dive)
6. [Jenkins Deep Dive](#6-jenkins-deep-dive)
   - [What is Jenkins?](#what-is-jenkins)
   - [Jenkinsfile — the Pipeline](#jenkinsfile--the-pipeline)
   - [Stage-by-stage breakdown](#stage-by-stage-breakdown)
7. [First-Time Setup: Step by Step](#7-first-time-setup-step-by-step)
8. [Auto-Deployment Flow](#8-auto-deployment-flow)
9. [Cheat Sheet — All Commands](#9-cheat-sheet--all-commands)
10. [Common Errors & Fixes](#10-common-errors--fixes)
11. [How Things Connect — Mental Model](#11-how-things-connect--mental-model)

---

## 1. The Big Picture — What & Why

As a senior FE dev you've probably had this experience:

> *"Works on my machine."*

Or the slightly worse version:

> *"The build passes locally but the server has a different Node version and everything is broken."*

**Docker** solves the environment problem. **Jenkins** solves the deployment automation problem. Together they form a **CI/CD pipeline** — a system that automatically builds, tests, and deploys your app every time you push code.

### What CI/CD actually means

| Term | Meaning | Analogy |
|---|---|---|
| **CI** (Continuous Integration) | Auto-run tests on every push | Like ESLint running on every save, but for the whole team |
| **CD** (Continuous Delivery/Deployment) | Auto-deploy passing builds | Like `npm run build && scp ...` but hands-free |

### Why not just use GitHub Actions or Vercel?

You can — and for many projects you should. But Jenkins is the industry standard in enterprise environments where:
- You need CI/CD on a **private network** (no access to GitHub's cloud runners)
- You want **full control** over the build environment
- Your team already has Jenkins infrastructure
- You need to integrate with internal tools (Jira, Nexus, SonarQube, etc.)

---

## 2. Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                      Your Windows Machine                    │
│                                                             │
│  ┌──────────────────────────────────────────────────────┐  │
│  │              Docker Desktop (Host Daemon)             │  │
│  │                                                      │  │
│  │  ┌─────────────────────────┐  ┌──────────────────┐  │  │
│  │  │   Jenkins Container     │  │  React App        │  │  │
│  │  │   (port 8080)           │  │  Container        │  │  │
│  │  │                         │  │  (port 3000)      │  │  │
│  │  │  - Node.js 18           │  │                  │  │  │
│  │  │  - Docker CLI           │  │  nginx serves     │  │  │
│  │  │  - Git                  │  │  /build output   │  │  │
│  │  │  - libatomic1           │  │                  │  │  │
│  │  └──────────┬──────────────┘  └──────────────────┘  │  │
│  │             │ docker.sock (talks to host daemon)      │  │
│  │             └─────────────────────────────────────►  │  │
│  └──────────────────────────────────────────────────────┘  │
│                                                             │
│  Persistent Volume: C:/jenkins-docker/jenkins_home          │
└─────────────────────────────────────────────────────────────┘
```

**Key insight:** Jenkins runs *inside* Docker, but it builds and deploys Docker images by talking to the *host* Docker daemon through `/var/run/docker.sock`. This is called **Docker-outside-of-Docker (DooD)**.

---

## 3. Project Structure Explained

```
basic-react-app-for-jenkins-learning/
│
├── src/                      # React source code (you already know this)
├── public/                   # Static assets
│
├── Dockerfile                # How to build the React app image (multi-stage)
├── Dockerfile.jenkins        # Custom Jenkins image with Node + Docker CLI
│
├── docker-compose.yml        # Run Jenkins for CI/CD
├── docker-compose.dev.yml    # Run the React app locally via Docker
│
├── Jenkinsfile               # The pipeline definition (what Jenkins runs)
├── nginx.conf                # Nginx config for serving the built React app
│
└── package.json              # Standard React app manifest
```

---

## 4. Docker Deep Dive

### What is Docker and why does a frontend dev care?

Think of Docker as **a way to package your app and its environment together**.

- A **Docker image** is like a blueprint (think: a snapshot of a configured OS + your app)
- A **Docker container** is a running instance of that image (like an opened app from the blueprint)
- A **Dockerfile** is the recipe that creates the image

The analogy for a React dev:

> Docker image ≈ the `node_modules` + your app + the OS, all zipped up  
> Container ≈ that zip, unzipped and running  
> Dockerfile ≈ the `.nvmrc` + `package.json` + setup script, merged into one

---

### Dockerfile (the React App image)

```dockerfile
# ---- Stage 1: Build ----
FROM node:18-alpine AS builder

WORKDIR /app

COPY package*.json ./
RUN npm install

COPY . .
RUN npm run build

# ---- Stage 2: Serve with Nginx ----
FROM nginx:alpine

COPY --from=builder /app/build /usr/share/nginx/html
COPY nginx.conf /etc/nginx/conf.d/default.conf

EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
```

**Why two stages (multi-stage build)?**

This is an important optimization pattern. Without it, your final image would contain Node.js, npm, all `node_modules`, and your source code — hundreds of MB just to serve static files.

| Stage | Base image | Purpose | Kept in final image? |
|---|---|---|---|
| `builder` | `node:18-alpine` | Install deps, run `npm run build` | ❌ No |
| final | `nginx:alpine` | Serve the `/build` output | ✅ Yes |

The final image is ~25MB instead of ~400MB. Only the compiled `/build` folder is copied into the nginx stage.

**Why nginx and not `react-scripts start`?**

`react-scripts start` is a **development server** — it includes hot reloading, source maps, unminified code, and has no performance optimizations. In production you serve the static output of `npm run build` via a proper web server like nginx.

---

### Dockerfile.jenkins (the custom Jenkins image)

```dockerfile
FROM jenkins/jenkins:lts

USER root

RUN apt-get update && apt-get install -y \
    libatomic1 \
    curl \
    git \
    ca-certificates \
    gnupg \
    lsb-release \
    && install -m 0755 -d /etc/apt/keyrings \
    && curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg \
    && chmod a+r /etc/apt/keyrings/docker.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
       https://download.docker.com/linux/debian $(lsb_release -cs) stable" \
       > /etc/apt/sources.list.d/docker.list \
    && apt-get update && apt-get install -y docker-ce-cli \
    && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL https://deb.nodesource.com/setup_18.x | bash - \
    && apt-get install -y nodejs \
    && rm -rf /var/lib/apt/lists/*

RUN node --version && npm --version && docker --version

USER jenkins
```

**Why do we need a custom Jenkins image instead of the official one?**

The official `jenkins/jenkins:lts` image ships with Java and Jenkins — nothing else. Our pipeline needs:

| Tool | Why needed |
|---|---|
| `libatomic1` | Node.js 18 binaries on Debian link against this system library. Without it, `node` crashes with `cannot open shared object file` |
| `curl`, `git` | Fetching scripts and cloning repos |
| `docker-ce-cli` | Running `docker build` / `docker run` commands inside pipeline stages |
| `nodejs` (via nodesource) | Running `npm install`, `npm test`, `npm run build` |
| `ca-certificates`, `gnupg` | Verifying Docker's GPG key for the apt repository (security requirement) |

**Why `USER root` then back to `USER jenkins`?**

`apt-get` requires root permissions. We elevate to root only for setup, then drop back to the `jenkins` user for actual runtime — least-privilege principle.

---

### docker-compose.yml (running Jenkins)

```yaml
version: '3.8'

services:
  jenkins:
    build:
      context: .
      dockerfile: Dockerfile.jenkins
    container_name: jenkins
    restart: unless-stopped
    privileged: true
    user: root
    ports:
      - "8080:8080"
      - "50000:50000"
    volumes:
      - C:/jenkins-docker/jenkins_home:/var/jenkins_home
      - //var/run/docker.sock:/var/run/docker.sock
    environment:
      - JAVA_OPTS=-Djenkins.install.runSetupWizard=false
```

| Config | Why |
|---|---|
| `build.dockerfile: Dockerfile.jenkins` | Use our custom image, not the plain Jenkins image |
| `restart: unless-stopped` | Auto-restart if the container crashes or the machine reboots |
| `privileged: true` + `user: root` | Required for Docker socket access on Windows/Docker Desktop |
| `8080:8080` | Jenkins web UI — `host:container` port mapping |
| `50000:50000` | Jenkins agent communication port (for when you add build agents later) |
| `C:/jenkins-docker/jenkins_home:/var/jenkins_home` | **Persistent volume** — Jenkins config, jobs, and build history survive container restarts |
| `//var/run/docker.sock:/var/run/docker.sock` | Shares the host Docker daemon socket with Jenkins (Docker-outside-of-Docker) |
| `JAVA_OPTS=-Djenkins.install.runSetupWizard=false` | Skips the initial setup wizard — useful when you already know your config |

**What is the Docker socket?**

`/var/run/docker.sock` is a Unix socket file — the API endpoint of the Docker daemon. When Jenkins runs `docker build`, it sends that command through the socket to the *host* Docker daemon, which actually builds the image. Jenkins doesn't run a Docker daemon itself — it just uses the host's.

---

### docker-compose.dev.yml (local dev preview)

```yaml
version: '3.8'

services:
  react-app:
    build: .
    container_name: react-dev
    ports:
      - "3000:80"
    restart: unless-stopped
```

This is for previewing the **production Docker build** locally without Jenkins. It builds the `Dockerfile` (multi-stage) and serves it on `http://localhost:3000`.

```bash
# Start local preview
docker-compose -f docker-compose.dev.yml up --build

# Stop it
docker-compose -f docker-compose.dev.yml down
```

---

## 5. Nginx Deep Dive

```nginx
server {
    listen 80;
    server_name localhost;

    root /usr/share/nginx/html;
    index index.html;

    # Handle React Router
    location / {
        try_files $uri $uri/ /index.html;
    }

    # Cache static assets
    location /static/ {
        expires 1y;
        add_header Cache-Control "public, immutable";
    }
}
```

**The React Router problem and why `try_files` solves it**

Without this config, if a user navigates directly to `http://yourdomain.com/dashboard`, nginx would look for a file at `/usr/share/nginx/html/dashboard` — which doesn't exist — and return a 404.

`try_files $uri $uri/ /index.html` tells nginx:
1. Try to serve the exact file (`$uri`)
2. Try to serve it as a directory (`$uri/`)
3. If neither exists, fall back to `/index.html` → React Router then handles the route client-side

**The static asset caching**

React's build output in `/static/` has content-hashed filenames (e.g., `main.abc123.js`). Because the filename changes when content changes, it's safe to cache these files for 1 year (`expires 1y`). The `immutable` directive tells the browser it never needs to revalidate — massive performance win.

---

## 6. Jenkins Deep Dive

### What is Jenkins?

Jenkins is an **automation server** — it watches for triggers (like a Git push), then runs a series of commands you define. Think of it like a GitHub Actions workflow, but self-hosted.

Key concepts:

| Term | What it is |
|---|---|
| **Pipeline** | The full CI/CD workflow definition |
| **Stage** | A named step in the pipeline (e.g., "Build", "Test") |
| **Agent** | The machine/container that runs the pipeline |
| **Jenkinsfile** | The file that defines the pipeline, stored in your repo |
| **Build** | One execution of the pipeline |

**Why store the Jenkinsfile in the repo?**

This is called **Pipeline-as-Code**. The pipeline definition lives alongside your source code, so:
- Every change to the pipeline is version-controlled
- Any developer can understand the full build+deploy process
- You can test pipeline changes in a branch before merging

---

### Jenkinsfile — the Pipeline

```groovy
pipeline {
    agent any

    environment {
        IMAGE_NAME     = 'react-app'
        IMAGE_TAG      = "${BUILD_NUMBER}"
        CONTAINER_NAME = 'react-app-container'
        PORT           = '3000'
        CI             = 'true'
    }

    stages {
        stage('Checkout') { ... }
        stage('Verify Node') { ... }
        stage('Install Dependencies') { ... }
        stage('Run Tests') { ... }
        stage('Build') { ... }
        stage('Docker Build') { ... }
        stage('Deploy') { ... }
    }

    post {
        success { ... }
        failure { ... }
    }
}
```

The Jenkinsfile uses **Declarative Pipeline syntax** (the recommended modern approach). It's written in Groovy but you only need to know a small subset.

---

### Stage-by-stage breakdown

#### `agent any`
Run the pipeline on any available Jenkins agent. Since we only have one (the Jenkins container itself), it runs there.

#### `environment {}`
Defines environment variables available to all stages. `BUILD_NUMBER` is a built-in Jenkins variable that auto-increments with each run — this becomes your Docker image tag, giving you versioned images (`react-app:10`, `react-app:11`, etc.).

Setting `CI = 'true'` tells `react-scripts test` to run in non-interactive mode (no watch mode).

#### `stage('Checkout')`
```groovy
git branch: 'master', url: 'https://github.com/...'
```
Jenkins clones the repo into its workspace (`/var/jenkins_home/workspace/react-app-pipeline`). Each build gets a fresh checkout.

#### `stage('Verify Node')`
```groovy
sh 'node --version && npm --version'
```
A sanity check. If this fails, you know immediately the issue is Node not being installed — before wasting time on `npm install`.

#### `stage('Install Dependencies')`
```groovy
sh 'npm install'
```
Same as running `npm install` locally. Jenkins runs this in the checked-out workspace directory.

#### `stage('Run Tests')`
```groovy
sh 'npm test -- --watchAll=false --passWithNoTests'
```
- `--watchAll=false` — critical in CI; without it, Jest enters watch mode and the pipeline hangs forever
- `--passWithNoTests` — don't fail if there are no test files yet (useful for early-stage projects)

#### `stage('Build')`
```groovy
sh 'npm run build'
```
Produces the optimized production output in `/build`. This is the output that gets copied into the Docker image.

#### `stage('Docker Build')`
```groovy
sh "docker build -t ${IMAGE_NAME}:${IMAGE_TAG} ."
sh "docker tag ${IMAGE_NAME}:${IMAGE_TAG} ${IMAGE_NAME}:latest"
```
- Builds the multi-stage `Dockerfile` using the workspace as context
- Tags it with the build number (e.g., `react-app:10`) for versioning
- Also tags as `latest` for easy "get the newest" reference

#### `stage('Deploy')`
```groovy
docker stop react-app-container || true
docker rm   react-app-container || true
docker run -d --name react-app-container -p 3000:80 --restart unless-stopped react-app:latest
```
- `|| true` — don't fail the pipeline if the container doesn't exist yet (first run)
- `docker stop` + `docker rm` — gracefully replace the old container (zero-downtime for a simple setup)
- `-d` — detached mode (runs in background; pipeline doesn't wait for it)
- `-p 3000:80` — maps port 80 inside the container (nginx) to port 3000 on the host

#### `post { success/failure }`
Runs after all stages regardless of outcome. Use this for notifications (Slack, email), cleanup, or reporting.

---

## 7. First-Time Setup: Step by Step

### Prerequisites

- Docker Desktop installed and running on Windows
- Git installed
- The project cloned locally

### Step 1 — Create the persistent volume directory

```bash
mkdir C:\jenkins-docker\jenkins_home
```

This directory stores all Jenkins data. Without it, every time you restart Jenkins you lose your jobs, credentials, and build history.

### Step 2 — Build and start Jenkins

```bash
# From the project root
docker-compose up --build -d
```

- `--build` — forces a rebuild of the custom Jenkins image (important on first run and after Dockerfile.jenkins changes)
- `-d` — detached mode (runs in background)

### Step 3 — Access Jenkins UI

Open `http://localhost:8080`

Since we set `JAVA_OPTS=-Djenkins.install.runSetupWizard=false`, the setup wizard is skipped. If you land on a login page with no credentials, the default is `admin` / check the logs:

```bash
docker logs jenkins | grep -i password
```

### Step 4 — Install recommended plugins

Jenkins → Manage Jenkins → Manage Plugins → Available → search and install:
- **Git plugin** (usually pre-installed)
- **Pipeline** (usually pre-installed)

> **Do NOT install the NodeJS Plugin.** Node.js is already baked into the custom image. The NodeJS Plugin would download a separate Node binary that may be missing system library dependencies like `libatomic.so.1`.

### Step 5 — Create the Pipeline job

1. Jenkins → **New Item**
2. Enter a name: `react-app-pipeline`
3. Select **Pipeline** → OK
4. Under **Pipeline definition** → select **Pipeline script from SCM**
5. SCM: **Git**
6. Repository URL: `https://github.com/panchal-nikki/jenkins-learnings.git`
7. Branch: `*/master`
8. Script Path: `Jenkinsfile`
9. Save

### Step 6 — Run the first build

Click **Build Now**. Watch the **Stage View** — each stage should turn green.

Your app will be running at `http://localhost:3000` after a successful deploy.

---

## 8. Auto-Deployment Flow

Right now the pipeline runs **manually** (you click "Build Now"). To make it fully automatic on every Git push, configure a **webhook**.

### Option A: GitHub Webhook (recommended)

1. In Jenkins → your pipeline → **Configure** → **Build Triggers** → check **GitHub hook trigger for GITScm polling**

2. In GitHub → your repo → **Settings → Webhooks → Add webhook**:
   - Payload URL: `http://YOUR_PUBLIC_IP:8080/github-webhook/`
   - Content type: `application/json`
   - Trigger: **Just the push event**

> **Note:** Jenkins must be reachable from the internet. If running locally on Windows, you'll need a tool like [ngrok](https://ngrok.com) to create a public tunnel:
> ```bash
> ngrok http 8080
> # Use the generated https URL as your webhook payload URL
> ```

### Option B: Polling (simpler, no public IP needed)

In Jenkins → your pipeline → **Configure** → **Build Triggers** → check **Poll SCM**

Schedule (cron syntax): `H/5 * * * *` — polls GitHub every 5 minutes.

Less efficient than webhooks (wastes resources, has up to 5-minute delay) but works without any network configuration.

### Full auto-deploy flow

```
Developer pushes to master
        │
        ▼
GitHub sends webhook to Jenkins
        │
        ▼
Jenkins clones the repo
        │
        ▼
npm install → npm test → npm run build
        │
        ├─── Tests fail? ──► Pipeline fails, sends notification
        │
        ▼ Tests pass
docker build (multi-stage, produces ~25MB nginx image)
        │
        ▼
Stop old container → Start new container on port 3000
        │
        ▼
App is live at http://localhost:3000
```

---

## 9. Cheat Sheet — All Commands

### Docker

```bash
# Build an image from a Dockerfile
docker build -t my-image:tag .

# Build using a specific Dockerfile
docker build -f Dockerfile.jenkins -t my-jenkins .

# List all images
docker images

# Remove an image
docker rmi my-image:tag

# Run a container
docker run -d --name my-container -p 3000:80 my-image:latest

# Stop a container
docker stop my-container

# Remove a container
docker rm my-container

# List running containers
docker ps

# List all containers (including stopped)
docker ps -a

# View container logs
docker logs my-container
docker logs -f my-container   # follow (live tail)

# Execute a command inside a running container
docker exec -it my-container bash

# Remove all stopped containers
docker container prune

# Remove all unused images
docker image prune -a
```

### Docker Compose

```bash
# Start services (build if needed)
docker-compose up -d

# Force rebuild images before starting
docker-compose up --build -d

# Use a specific compose file
docker-compose -f docker-compose.dev.yml up --build -d

# Stop and remove containers
docker-compose down

# Stop, remove containers AND delete volumes
docker-compose down -v

# View logs
docker-compose logs -f

# View logs for a specific service
docker-compose logs -f jenkins
```

### Jenkins

```bash
# View Jenkins logs
docker logs jenkins

# Tail Jenkins logs live
docker logs -f jenkins

# Restart Jenkins container
docker restart jenkins

# Rebuild the Jenkins image and restart
docker-compose down
docker-compose up --build -d

# Open a shell inside Jenkins container (for debugging)
docker exec -it jenkins bash

# Check Node.js version inside Jenkins
docker exec jenkins node --version

# Check Docker CLI version inside Jenkins
docker exec jenkins docker --version
```

---

## 10. Common Errors & Fixes

### `libatomic.so.1: cannot open shared object file`

**Cause:** Node.js 18 binary requires `libatomic1` system library, which isn't installed.

**Fix:** Ensure `libatomic1` is in your `Dockerfile.jenkins` `apt-get install` list. Then rebuild:
```bash
docker-compose down && docker-compose up --build -d
```

---

### `docker: not found`

**Cause:** Docker CLI is not installed inside the Jenkins container. The Docker socket mount alone doesn't provide the CLI.

**Fix:** Add Docker CLI installation to `Dockerfile.jenkins` (see the file in this repo). Rebuild the container.

---

### `npm test` hangs indefinitely

**Cause:** Jest enters interactive watch mode in a terminal that doesn't support it.

**Fix:** Always pass `--watchAll=false` in CI:
```groovy
sh 'npm test -- --watchAll=false'
```

---

### Jenkins setup wizard keeps appearing

**Cause:** `JAVA_OPTS` environment variable not set, or the volume already has a pre-wizard state.

**Fix:** Ensure this is in `docker-compose.yml`:
```yaml
environment:
  - JAVA_OPTS=-Djenkins.install.runSetupWizard=false
```

---

### Old container won't stop during deploy stage

**Cause:** Trying to `docker stop` a container that doesn't exist yet (first run).

**Fix:** Always append `|| true` to destructive commands in pipelines:
```bash
docker stop react-app-container || true
docker rm react-app-container || true
```

---

### Build number tag keeps incrementing but old images pile up

**Fix:** Add a cleanup step to your Jenkinsfile `post` block:
```groovy
post {
    success {
        sh "docker image prune -f"
    }
}
```

---

## 11. How Things Connect — Mental Model

Here is the complete data flow from code push to live app:

```
Your Code (React)
    │
    │  git push
    ▼
GitHub Repository
    │
    │  webhook / poll
    ▼
Jenkins (port 8080)
  runs inside Docker container
  has: Node.js 18, Docker CLI, Git
    │
    ├─ git clone → workspace
    ├─ npm install
    ├─ npm test
    ├─ npm run build  →  /build (static HTML/CSS/JS)
    │
    ├─ docker build   →  reads Dockerfile
    │                    Stage 1: node:18-alpine → npm install + npm run build
    │                    Stage 2: nginx:alpine   → copy /build, add nginx.conf
    │                    Result: react-app:11 (~25MB image)
    │
    ├─ docker stop react-app-container
    ├─ docker rm   react-app-container
    └─ docker run  react-app:latest  →  new container on port 3000
                                         nginx serves /build
                                         React Router handled by try_files

User visits http://localhost:3000
    │
    ▼
nginx container
  → serves index.html + hashed static assets
  → all routes fall back to index.html (React Router)
  → /static/* cached for 1 year
```

### The key insight

Jenkins doesn't have special deploy magic. It just runs the same `docker build` and `docker run` commands you would run manually in your terminal — but automatically, on every push, with test gates in between. That's CI/CD.