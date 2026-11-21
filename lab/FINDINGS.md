# Findings — Part 4 debug lab

Fill in one entry per defect you find. Paste the *actual* output you saw —
we cross-check it against your session recording and your git diff, and the
diagnostic path matters more to us than the fix itself.

Before you start investigating, begin recording:
`script -q part4-session.log` (or `asciinema rec part4-session.cast`), and
commit that file alongside this one.

---

## Defect 1

**Symptom:**

When I ran `./scenario.sh up`, the migration Job failed with this error:

```
Job.batch "migrate" is invalid: spec.template.spec.restartPolicy: Required value: valid values: "OnFailure", "Never"
```

**Cause:**

The migrate Job's `restartPolicy` was set to `Always` at line 16 of `broken-chart/templates/migrate-job.yaml`. Kubernetes Jobs only accept `Never` or `OnFailure`, so the Job was rejected.

**Fix:**

Changed the value in `broken-chart/templates/migrate-job.yaml`:

- Before: `restartPolicy: Always`
- After: `restartPolicy: Never`

I chose `Never` because each retry creates a new pod, instead of restarting the same container. The number of retries is controlled by `backoffLimit`.

**How I found it:**

1. Ran `./scenario.sh up` and got the migrate Job error.
2. Read the error message, which named `restartPolicy` and listed the valid values.
3. Ran `cat -n broken-chart/templates/migrate-job.yaml` to see the file with line numbers.
4. Found the wrong value on line 16 and changed it from `Always` to `Never`.
5. Confirmed the change with `grep -n restartPolicy broken-chart/templates/migrate-job.yaml`.
---

## Defect 2

**Symptom:**

After deploying the lab, I ran `kubectl -n debug-lab get pods`. All app pods and the migrate Job were stuck in `CreateContainerConfigError`. The events showed this error:

```
Error: container has runAsNonRoot and image has non-numeric user (nonroot), cannot verify user is non-root
```

**Cause:**

The Helm templates set `runAsNonRoot: true` but did not set a numeric user ID. The image's user is the name `nonroot`, which is UID `65532`. Kubernetes needs a number to confirm the container is not running as root, so it refused to start the containers.

**Fix:**

I added `runAsUser: 65532` under `runAsNonRoot: true` in six templates: `backend.yaml`, `gateway.yaml`, `worker.yaml`, `reporter.yaml`, `metrics.yaml` and `migrate-job.yaml`.

Before:

```
runAsNonRoot: true
```

After:

```
runAsNonRoot: true
runAsUser: 65532
```

I used the numeric UID because `runAsUser` needs a number, not a username.

I also deleted and recreated the migrate Job, because Kubernetes does not allow changes to an existing Job's pod template. Helm could not update it in place.

**How I found it:**

1. Ran `kubectl -n debug-lab get pods` and saw `CreateContainerConfigError`.
2. Ran `kubectl -n debug-lab get events --sort-by=.lastTimestamp` and found the `runAsNonRoot ... non-numeric user` message.
3. Ran `grep -rn -i "runAs\|securityContext" broken-chart/` and saw that each template set `runAsNonRoot` with no user ID.
4. Ran `docker pull` and `docker inspect` on the image, which showed its user is `nonroot`.
5. Ran `docker create`, `docker cp` and `tar` to read `/etc/passwd` inside the image, which showed `nonroot:x:65532:65532`.
6. Added `runAsUser: 65532` to the six templates and checked with `grep -rn runAsUser broken-chart/`, which showed six matches.
7. Deleted the old migrate Job with `kubectl -n debug-lab delete job migrate`, then ran `./scenario.sh up`.
---

## Defect 3

**Symptom:**

The backend and gateway pods were failing their readiness checks. `kubectl describe pod` showed the probe failing with `connection refused` on port 8080, while the application logs said `listening on :8081`.

**Cause:**

The chart never set the `PORT` environment variable, so the application used its default port, 8081. The readiness probe and Service were configured for port 8080, so the probe couldn't connect.

**Fix:**

I added `PORT: "8080"` under the `env:` block for the backend in `broken-chart/values.yaml`:

```
env:
  PORT: "8080"
```

I chose this over changing the port in the chart because the Service and probes were already set to 8080. Changing the app's port keeps the rest of the configuration consistent.

The gateway has the same problem and needs the same change. At the time of writing, I had not yet confirmed the gateway fix. This is still in progress.

**How I found it:**

1. Ran `kubectl -n debug-lab describe pod` and saw the readiness probe failing with `connection refused` on port 8080.
2. Ran `kubectl -n debug-lab logs` and saw the app listening on `:8081`.
3. Ran `grep -rn -i "port"` on `values.yaml` and `backend.yaml`, which showed the probe using `common.port` (8080) and no `PORT` variable set.
4. Added `PORT: "8080"` to the backend's env block, then ran `./scenario.sh up`.
5. Confirmed with the backend log (`/healthz -> 200`) and `./scenario.sh verify`, which now passes the backend check.
---

## Defect 4

**Symptom:**

After the port fix, the gateway's readiness check failed. The gateway log showed:

```
readiness failed: backend not reachable: GET http://backend.default.svc:8080/healthz: ... lookup backend.default.svc on 10.96.0.10:53: no such host
```

`verify` also reported `gateway /status does not report backend=ok`.

**Cause:**

The gateway's `BACKEND_URL` in `broken-chart/values.yaml` pointed at namespace `default`, but the backend runs in namespace `debug-lab`. DNS couldn't resolve a host in a namespace that doesn't have the backend, so the gateway couldn't reach it.

**Fix:**

I changed the namespace in `BACKEND_URL` from `default` to `debug-lab`, so the value is `http://backend.debug-lab.svc:8080`. I kept the rest of the URL the same, since the backend's Service is named `backend` and listens on port 8080.

**How I found it:**

1. Ran `kubectl -n debug-lab logs <gateway-pod> --tail=5` and saw the `no such host` error.
2. Read the hostname in the error (`backend.default.svc`) and compared it with the namespace the lab runs in (`debug-lab`).
3. Ran `grep -n -A6 "^gateway:" broken-chart/values.yaml` and found `BACKEND_URL` on line 39.
4. Changed the namespace, ran `./scenario.sh up`, then `./scenario.sh verify`. The check `gateway /status reports backend=ok` passed.

---

## Defect 5

**Symptom:**

The metrics pod was never created. `kubectl -n debug-lab get events` showed:

```
replicaset/metrics-...  (combined from similar events): Error creating: pods "metrics-..." is forbidden: maximum cpu usage per Container is 1, but limit is 4
```

**Cause:**

The metrics block in `broken-chart/values.yaml` set a CPU request of `"2"` and a CPU limit of `"4"`. The cluster's LimitRange in `cluster-state/limits.yaml` caps each container at 1 CPU, so Kubernetes refused to create the pod.

**Fix:**

I changed the metrics CPU request to `50m` and the limit to `200m`, matching the other services in the same file. I didn't change `cluster-state/limits.yaml`, because that directory must stay unchanged.

**How I found it:**

1. Ran `kubectl -n debug-lab get events --sort-by=.lastTimestamp | tail -10` and saw the `forbidden` message.
2. Ran `grep -n -A10 "^metrics:" broken-chart/values.yaml` and found the CPU values `"2"` and `"4"`.
3. Compared them with `cluster-state/limits.yaml`, which sets `max: cpu: "1"`.
4. Changed the values, ran `./scenario.sh up` and `./scenario.sh verify`. The metrics deployment check then passed.


## Defect 6

**Symptom:**

The worker pod was in `CrashLoopBackOff`. The previous container's log said:

```
FATAL: worker could not initialise its cache: mkdir /var/cache/app: read-only file system
```

**Cause:**

The worker's container sets `readOnlyRootFilesystem: true` in `broken-chart/templates/worker.yaml`, which makes the whole filesystem read-only. The app needs to create a cache folder at `/var/cache/app`, and nothing was mounted there, so it crashed on startup.

**Fix:**

I kept `readOnlyRootFilesystem: true`, since it's a good security setting, and gave the app a writable place to store its cache. In `broken-chart/templates/worker.yaml` I added:

- a `volumes:` entry under the pod spec, with a volume named `cache` backed by `emptyDir: {}`
- a `volumeMounts:` entry under the container, mounting `cache` at `/var/cache/app`

I chose this over setting `CACHE_DIR` because the mount keeps the read-only root filesystem in place. The app gets exactly one writable folder, and it's temporary, which fits a cache.

I also added `PORT: "8080"` to the worker's `env:` block in `values.yaml`, since the worker was listening on 8081, like the others (see Defect 3).

**How I found it:**

1. Ran `kubectl -n debug-lab get pods -l app=worker` and saw `CrashLoopBackOff`.
2. Ran `kubectl -n debug-lab logs worker-<pod> --previous` and found the read-only filesystem error.
3. Ran `cat -n broken-chart/templates/worker.yaml` to see the container and pod structure.
4. Added the volume and mount. My first attempts had the wrong indentation, which Helm reported as a YAML parse error. I used `awk` to measure the indentation of the key lines, then placed the blocks to match.
5. Ran `./scenario.sh up` and checked the worker with `kubectl -n debug-lab logs` on the new pod. It started without the cache error, then passed `verify` after the `PORT` fix.
---

## Defect 7 (open)

**Symptom:**

The reporter pod stays `0/1` and `verify` still fails the reporter deployment check and the `/report` check. Its log shows:

```
pod list failed: parse pod list: unexpected end of JSON input
```

**Cause:**

Not found. The earlier 403 error was a separate defect, now fixed. This new error means the API call succeeds at the network level but returns an empty or incomplete response, so the app can't parse the pod list.

**Fix:**

Not yet fixed. Changes already made that relate to the reporter:

- Added `PORT: "8080"` to the reporter's `env:` block in `values.yaml` (see Defect 3). The app now listens on 8080.
- Changed the RoleBinding subject from `default` to `reporter` in `rbac.yaml` (see the RBAC defect). The 403 is gone.

**How I found it:**

1. Ran `kubectl -n debug-lab logs <reporter-pod> --tail=3` and saw the parse error.
2. Ran `kubectl -n debug-lab describe pod <reporter-pod> | grep -A3 -i "mounts\|serviceaccount"`. The ServiceAccount token is mounted normally.
3. Checked `broken-chart/templates/reporter.yaml`. It doesn't set any token, volume or API options; it only loops over `.Values.reporter.env`.

**What I would try next:**

- Find out what settings the reporter app expects in its environment. For example, a namespace variable could be missing, which would make it build a broken API request and get an empty answer.
- Test the API call directly from a pod running as the `reporter` ServiceAccount, to see what the API really returns.
- Compare the reporter's env with the other workloads, looking for a setting the reporter needs but doesn't have.
If you ran out of time on any defect, say so here and describe what you would
have tried next — that section is read carefully and counts in your favour.

 -------
