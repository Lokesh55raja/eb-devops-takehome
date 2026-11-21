# syntax=docker/dockerfile:1
# Pinned base image (never :latest). Bump deliberately, rebuild, re-run tests.
ARG NODE_IMAGE=node:22.11.0-bookworm-slim

# ---- build stage: run the unit tests; nothing from here ships ----
FROM ${NODE_IMAGE} AS build
WORKDIR /src
COPY package.json app.js app.test.js ./
RUN node --test

# ---- runtime stage: only the app files, no tests, no npm ----
FROM ${NODE_IMAGE} AS runtime
ENV NODE_ENV=production \
    PORT=8080
WORKDIR /app
COPY --from=build --chown=1000:1000 /src/app.js /src/package.json ./
# Numeric UID so Kubernetes can verify runAsNonRoot.
USER 1000:1000
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD ["node", "-e", "require('http').get('http://127.0.0.1:'+(process.env.PORT||8080)+'/healthz',r=>process.exit(r.statusCode===200?0:1)).on('error',()=>process.exit(1))"]
CMD ["node", "app.js"]
