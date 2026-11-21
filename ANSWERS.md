# Part 5 — Answers

> **Draft written with AI help. Rewrite in your own words before submitting. You must be able to defend every bullet live.**

## Q1. Migrating about 40 Ingresses on ingress-nginx (end-of-life) to the Gateway API, without downtime

**Approach and order**

- **Inventory first.** Export all Ingresses. Flag every annotation (rewrite-target, auth, rate limits, timeouts, body size, `configuration-snippet`). Those are the parts that will not translate cleanly.
- **Run side by side.** Install a conformant Gateway API controller with its own LoadBalancer IP. ingress-nginx keeps serving traffic, so nothing moves yet.
- **Convert, then review by hand.** Use `ingress2gateway` to generate draft HTTPRoutes. Its output is lossy for custom annotations, so review each route.
- **Verify before cutover.** Test each route against the new IP (for example `curl --resolve host:443:<new-ip>`) and compare responses with the old path.
- **Move hostnames in small batches.** Lower DNS TTLs in advance. Switch one batch at a time, and keep the old Ingress and DNS record for a rollback window.
- **Remove ingress-nginx last**, once every host has been on the new path past the rollback window.

**What I expect to break**

- Annotations with no Gateway API equivalent, or with different defaults.
- Path matching differences: Prefix vs PathPrefix, trailing slashes, regex.
- TLS: certificate secrets referenced across namespaces need a ReferenceGrant.
- Client IP handling and `externalTrafficPolicy` changes.
- The new LoadBalancer IP breaking allowlists or hardcoded addresses.
- Route ownership across teams, which needs RBAC changes.

Because ingress-nginx is end-of-life, it receives no security fixes, so the timeline is driven by that risk.
