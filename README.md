# Support Engineering Lab — End-to-End Java Stack on Kubernetes

> A hands-on lab that takes a simple Java web application from source code all the way to a Kubernetes cluster, with monitoring, rolling updates, rollback, database backups, and an operational runbook.

Built as a self-directed learning project to practise the day-to-day skills of a Support / Implementation Engineer: building, deploying, debugging, and recovering a production-style stack.

-----

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                     Kubernetes Cluster (minikube)               │
│                                                                 │
│   ┌────────────────────┐         ┌─────────────────────────┐    │
│   │   Service          │         │   Deployment            │    │
│   │  (NodePort 30xxx)  │────────▶│   replicas: 2           │    │
│   └────────────────────┘         │   ┌─────────┐ ┌───────┐ │    │
│                                  │   │ Pod     │ │ Pod   │ │    │
│            ConfigMap ──env──▶    │   │ Tomcat 9│ │ Tomcat│ │    │
│            Secret    ──env──▶    │   │ + WAR   │ │ + WAR │ │    │
│                                  │   └─────────┘ └───────┘ │    │
│                                  └─────────────────────────┘    │
└─────────────────────────────────────────────────────────────────┘
                                  │
                                  ▼
                ┌──────────────────────────────────┐
                │   Oracle 21c XE (Docker)         │
                │   - app schema                   │
                │   - Data Pump backups            │
                └──────────────────────────────────┘
```

**Stack:** Java Servlet → Maven → WAR → Docker → Tomcat 9 → Kubernetes → Oracle 21c

-----

## Tech Stack

|Layer           |Technology                          |
|----------------|------------------------------------|
|Language        |Java 11                             |
|Build tool      |Apache Maven                        |
|App server      |Apache Tomcat 9                     |
|Containerization|Docker, Docker Compose              |
|Orchestration   |Kubernetes (minikube), kubectl      |
|Database        |Oracle Database 21c Express Edition |
|Backup          |Oracle Data Pump (`expdp` / `impdp`)|
|Automation      |Bash scripting                      |
|OS              |Ubuntu 22.04 / 24.04                |
|Editor / tools  |VS Code, Git                        |

-----

## Repository Layout

```
.
├── README.md                       # This file
├── pom.xml                         # Maven build descriptor
├── Dockerfile                      # Container image definition
├── docker-compose.yml              # Multi-service local stack (app + Oracle)
├── deploy.yaml                     # Kubernetes Deployment + Service
├── configmap-secret.yaml           # Kubernetes ConfigMap + Secret
├── runbook.md                      # Operational runbook
├── scripts/
│   └── build-and-deploy.sh         # Automated build → deploy → verify pipeline
└── src/
    └── main/
        ├── java/com/example/app/
        │   └── HelloServlet.java   # The Java Servlet
        └── webapp/WEB-INF/
            └── web.xml             # Servlet mapping
```

-----

## What This Lab Covers

### 1. Build

- A Java Servlet (`HelloServlet.java`) is compiled and packaged as a WAR with Maven.
- `pom.xml` declares the `javax.servlet-api` dependency at `provided` scope (Tomcat supplies it at runtime).

### 2. Containerize

- A minimal `Dockerfile` based on `tomcat:9.0-jdk11` copies the WAR into `webapps/`.
- `docker-compose.yml` brings up the app alongside Oracle XE with a persistent volume for the database.

### 3. Orchestrate with Kubernetes

- `deploy.yaml` defines a Deployment with **2 replicas** and a NodePort Service.
- `configmap-secret.yaml` externalises configuration:
  - **ConfigMap** for the JDBC URL (non-sensitive).
  - **Secret** for the database username and password.

### 4. Production-grade reliability

- **Readiness probe** ensures Kubernetes only sends traffic to pods that are ready to serve.
- **Liveness probe** restarts a pod that becomes unresponsive.
- **Rolling updates** with automatic verification; failed deploys are caught before they take down the service.
- **Rollback** demonstrated with `kubectl rollout undo`.

### 5. Database operations

- Schema creation, user management, and SQL via `sqlplus`.
- Logical backups and restores using **Oracle Data Pump** (`expdp` / `impdp`).
- Verified end-to-end: drop a table, restore from the dump, confirm row counts.

### 6. Monitoring & troubleshooting

- Container and pod logs via `docker logs` and `kubectl logs`.
- JVM diagnostics: thread dumps with `jstack`, heap inspection with `jmap`.
- `kubectl describe` and event analysis for incident triage.

### 7. Automation

- `scripts/build-and-deploy.sh` is a 5-step mini CI/CD pipeline:
1. `mvn clean package`
1. `docker build`
1. `minikube image load`
1. `kubectl set image` + `rollout status`
1. HTTP smoke test of the live endpoint.

### 8. Operational runbook

- `runbook.md` documents how an on-call engineer would:
  - Verify service health.
  - Locate logs.
  - Handle the most common failures (`CrashLoopBackOff`, `ImagePullBackOff`, DB connection errors).
  - Rollback, restart, or scale the deployment.
  - Restore the database from a Data Pump dump.

-----

## Quick Start

> Requires: Linux (Ubuntu recommended), Java 11+, Maven, Docker, kubectl, minikube.

```bash
# 1. Build the WAR
mvn clean package

# 2. Build the Docker image
docker build -t hello-web:1.0 .

# 3. Start Kubernetes
minikube start --driver=docker --cpus=2 --memory=2200
kubectl create namespace demo

# 4. Load the image into the cluster
minikube image load hello-web:1.0

# 5. Apply config and deployment
kubectl apply -f configmap-secret.yaml
kubectl apply -f deploy.yaml

# 6. Verify
kubectl get pods -n demo
curl $(minikube service hello-svc -n demo --url)/hello-web/
# Expected: Hello from Tomcat in container
```

For an automated end-to-end flow, run:

```bash
./scripts/build-and-deploy.sh
```

-----

## Issues Diagnosed and Resolved While Building This

A non-exhaustive list of real incidents I worked through, with the techniques that fixed them. This was the most valuable part of the lab.

|#|Symptom                                                     |Root cause                                                                           |How I diagnosed                                                                               |
|-|------------------------------------------------------------|-------------------------------------------------------------------------------------|----------------------------------------------------------------------------------------------|
|1|`kubectl` download produced an XML error file               |Deprecated `storage.googleapis.com/kubernetes-release` bucket                        |Inspected file size (133 B), opened the file                                                  |
|2|Maven compile failed: `package javax.servlet does not exist`|`servlet-api` dependency missing from `pom.xml`                                      |Read the `[ERROR]` lines in Maven output                                                      |
|3|Tomcat returned `HTTP 404` for the app                      |Default `index.jsp` from the archetype was masking the servlet `/`                   |Tested `/hello-web/anything` and got the servlet response                                     |
|4|Tomcat deployed but `404 /hello-web/`                       |`web.xml` had been overwritten with `pom.xml` content                                |`cat web.xml` in the deployed app, `catalina.out` showed XML parse errors                     |
|5|`docker run` failed: `port 1521 is already allocated`       |An old `oracle-xe` container from a previous session was still running               |`docker ps -a` and `docker ps --format ... | grep 1521`                                       |
|6|`expdp` and `impdp` failed with `ORA-01017`                 |The app user was lost when Oracle was restarted without the persistent volume        |`SELECT username FROM dba_users` as `sys`                                                     |
|7|Bad image tag rolled out to k8s                             |`kubectl set image deployment/... hello=hello-web:does-not-exist` to simulate failure|Pod status `ImagePullBackOff`; old pods kept serving — `kubectl rollout undo` restored service|
|8|Pod deleted to test self-healing                            |Simulated incident drill                                                             |ReplicaSet auto-created a replacement in ~15 s; service continued serving                     |

The runbook (`runbook.md`) captures the playbook for handling these and other scenarios going forward.

-----

## Skills Demonstrated

- **Linux administration** — Ubuntu, Bash, log inspection, port and process management.
- **Java application deployment** — Maven build, WAR packaging, Tomcat datasource configuration.
- **Containerization** — Dockerfile authoring, image build, port and volume management.
- **Orchestration** — Kubernetes Deployments, Services, ConfigMaps, Secrets, Probes, Rolling updates, Rollback.
- **Database administration** — Oracle user/schema management, SQL, Data Pump backup/restore.
- **Troubleshooting** — Log analysis, `kubectl describe`/`events`, JVM thread dumps, root-cause analysis.
- **Documentation** — Runbook authoring for on-call engineers.
- **Automation** — Shell scripting for repeatable build-and-deploy workflows.

-----

## Next Steps / Possible Extensions

- Add Prometheus + Grafana for metrics (via the `kube-prometheus-stack` Helm chart).
- Add an Ingress controller and TLS termination instead of `NodePort`.
- Replace local Oracle with a managed-DB pattern, and use Kubernetes Secrets sourced from Vault.
- Wire the build script into a real CI system (GitHub Actions or Jenkins).
- Add automated tests in the build stage so the rollout pipeline fails fast.

-----

## Author

**Yaqeen Alasouli** — Amman, Jordan  
Electronics Engineering graduate, Yarmouk University (2025).  

📧 [samouryageen@gmail.com](mailto:samouryageen@gmail.com)
