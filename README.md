# EB DevOps take-home

A small HTTP service, containerized, deployed to a local kind cluster with a Helm chart and a one-command setup script. Part 4 (the debug lab) lives in `lab/`.

**Status (be precise):** the service's unit tests pass. The Docker build, kind, Helm and `setup.sh` have **not yet been run** on the machine this was written on (no Docker/kind/helm there). They must be run on the Ubuntu machine using the steps below, and this section updated with the real results before submission.

| Part | Status |
|---|---|
| 1. Service + Dockerfile | Code and 5 unit tests written and passing (`node --test`). Image build not yet run. |
| 2. Helm chart | Written. `helm lint` / `helm template` not yet run. |
| 3. `setup.sh` | Written. Not yet run (needs Docker + kind). Idempotency not yet verified. |
| 4. Debug lab | Not done here. Must be done on your own cluster, with your own recording. |
| 5. ANSWERS.md | Draft. Must be rewritten in your own words. |
| 6. README | This file. |

## Layout

```
setup.sh          one-command kind + ingress-nginx + image + helm setup
service/          app.js, app.test.js, package.json, Dockerfile, .dockerignore
chart/            Helm chart: Deployment, Service, ConfigMap, Ingress
lab/              Part 4 handout, copied unchanged (fixes go in lab/broken-chart)
ANSWERS.md        Part 5
```

## How to run (Ubuntu)

Prerequisites: Docker Engine (your user in the `docker` group), `kind`, `kubectl`, `helm`, `curl`. Ports 80 and 443 on the host must be free.

```bash
git clone <your-repo-url> eb-devops-takehome
cd eb-devops-takehome
./setup.sh          # first run
./setup.sh          # second run must also exit 0 (idempotency)
```

Optional, to use the hostname in a browser or with plain `curl`:

```bash
echo "127.0.0.1 demo.local" | sudo tee -a /etc/hosts
```

## How to verify

```bash
# cluster objects
kubectl -n demo get deploy,pods,svc,ingress,configmap

# service through the ingress
curl -H 'Host: demo.local' http://localhost/          # {"app":"demo-app","version":"0.1.0","pod":"..."}
curl -H 'Host: demo.local' http://localhost/healthz   # {"status":"ok"}

# two replicas answer: run several times, the "pod" value should vary
for i in 1 2 3 4; do curl -s -H 'Host: demo.local' http://localhost/ ; echo; done

# override values (chart must follow)
helm template demo chart --set replicaCount=3 --set config.appName=shop --set config.version=9.9.9 \
  | grep -E 'replicas:|APP_NAME|VERSION'

# lint and unit tests
helm lint chart
(cd service && node --test)
```

Changing the app name or version on a running cluster:

```bash
helm upgrade demo chart -n demo --reuse-values --set config.version=0.2.0
curl -H 'Host: demo.local' http://localhost/          # version is now 0.2.0
```

## Resource requests and limits, and why

| | Request | Limit |
|---|---|---|
| CPU | 50m | 200m |
| Memory | 64Mi | 128Mi |

- **Requests** are what the scheduler reserves. The app is an idle Node.js process that answers small JSON requests, so 50m CPU and 64Mi cover it with margin. Small requests let both replicas fit on a single kind node next to ingress-nginx.
- **Memory limit 128Mi** is about 2x the typical resident size of a Node process. Node garbage-collects inside its heap, so a limit that is too tight gets the container OOM-killed; too loose hides leaks. 
- **CPU limit 200m** can throttle Node's startup, which uses more CPU than steady state. This may slow readiness on a cold start. I did not load-test these numbers, so treat them as a reasoned starting point, not measured values.

## What I deliberately skipped, and the risk

- **Config changes via `kubectl patch` do not roll pods.** Env vars from a ConfigMap are read at process start. A `helm upgrade` does roll pods, through the `checksum/config` annotation, but a direct ConfigMap patch does not. The app is also required to read env vars, so it cannot pick up changes without a restart. In production I would use a reloader (for example stakater Reloader) or mount the config as files and re-read them.
- **No HorizontalPodAutoscaler and no PodDisruptionBudget.** A node drain could take both replicas down together. Risk: brief outage during maintenance.
- **No TLS on the Ingress.** It serves plain HTTP on `demo.local`. Risk: credentials or data in transit would be exposed in any real environment. cert-manager would be the next step.
- **No NetworkPolicy.** Any pod can reach the service. Risk: lateral movement from a compromised pod.
- **No image vulnerability scan** (the optional Trivy job). Risk: shipping known CVEs in the base image. I pinned the base image tag but did not scan it.
- **`setup.sh` smoke check only warns** if the ingress is not reachable, so a re-run can't fail just because the controller is still warming up. Risk: a broken ingress can pass setup silently. The `kubectl` commands in "How to verify" catch this.
- **Image pinned to `node:22.11.0-bookworm-slim`** without a digest. Pinning by digest would make builds fully reproducible.
- **ingress-nginx is end-of-life.** `setup.sh` installs it because the brief asks for it. It should not be used for anything beyond this exercise. See `ANSWERS.md`.
- **`setup.sh` installs an ingress-nginx chart version I did not verify on a live cluster** (`4.11.3`). If `helm upgrade --install` fails on that version, check `helm search repo ingress-nginx/ingress-nginx --versions` and set `INGRESS_NGINX_CHART_VERSION`.

## What I would change for production

1. Move config to a reloadable source (or a GitOps tool such as Argo CD) with a proper rollout on change.
2. Add an HPA, PDB, `topologySpreadConstraints` and a readiness gate tied to dependencies.
3. TLS via cert-manager, and a Gateway API route instead of an Ingress, given ingress-nginx's EOL.
4. NetworkPolicy default-deny with explicit allows.
5. CI: lint (`helm lint`, `hadolint`), build, Trivy scan failing on HIGH/CRITICAL, then push to a registry with digests. The image should then be pulled, not `kind load`ed.
6. Observability: the `/healthz` endpoint is liveness only. Add metrics and structured logs, plus alerts on the SLO.

## How I used AI

> **Draft. Edit this to match what actually happened before you submit it.**

- Tool: Claude (Claude Code, Haiku 5.5), in one session.
- Used for: drafting the service code, tests, Dockerfile, Helm chart, `setup.sh`, and the first drafts of this README and `ANSWERS.md`, from the assignment text.
- Checked by me: the service tests were run and pass. Nothing else has been run yet.
- What I had to correct: _[fill in: e.g. the ingress-nginx version, any template or script fix you made after running it]_
- Not AI-written: Part 4. Every defect in the lab, and the session recording, is my own work on my own cluster.
