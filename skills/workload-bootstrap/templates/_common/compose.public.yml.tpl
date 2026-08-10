# Raw Docker Compose deployment per platform ADR-0011 §1.
#
# Coolify Domain field per service is LEFT EMPTY — routing is workload-owned
# via the Traefik labels below. Coolify magic variables (${COOLIFY_*}) only
# substitute inside `environment:` blocks, never inside `labels:`, so we
# hardcode the hostname here.
#
# Hostname follows ADR-0012 (nip.io hex form) until a real domain exists.
# Identity model: PUBLIC — no Authentik forward-auth on this workload.

services:
  {{NAME}}:
    build:
      context: .
    restart: unless-stopped
    environment:
      PORT: '{{PORT}}'
      HOST: 0.0.0.0
    networks:
      - coolify
    expose:
      - '{{PORT}}'
    labels:
      - traefik.enable=true
      - traefik.docker.network=coolify

      # ── Primary router (HTTPS), public ─────────────────────────────────
      # No auth middleware. Reachable directly.
      - "traefik.http.routers.{{NAME}}.rule=Host(`{{HOSTNAME}}`)"
      - traefik.http.routers.{{NAME}}.entrypoints=https
      - traefik.http.routers.{{NAME}}.tls=true
      - traefik.http.routers.{{NAME}}.tls.certresolver=letsencrypt
      - traefik.http.routers.{{NAME}}.priority=10
      - traefik.http.routers.{{NAME}}.service={{NAME}}

      # ── Auth-exempt /healthz router (ADR-0002) ────────────────────────
      # Even on public workloads we keep this router explicit so future
      # promotion to `protected` is a one-line label change without
      # accidentally gating the orchestrator probe.
      - "traefik.http.routers.{{NAME}}-healthz.rule=Host(`{{HOSTNAME}}`) && Path(`/healthz`)"
      - traefik.http.routers.{{NAME}}-healthz.entrypoints=https
      - traefik.http.routers.{{NAME}}-healthz.tls=true
      - traefik.http.routers.{{NAME}}-healthz.tls.certresolver=letsencrypt
      - traefik.http.routers.{{NAME}}-healthz.priority=100
      - traefik.http.routers.{{NAME}}-healthz.service={{NAME}}

      # ── HTTP → HTTPS bump (port 80) ────────────────────────────────────
      - "traefik.http.routers.{{NAME}}-http.rule=Host(`{{HOSTNAME}}`)"
      - traefik.http.routers.{{NAME}}-http.entrypoints=http
      - traefik.http.routers.{{NAME}}-http.middlewares=redirect-to-https@file
      - traefik.http.routers.{{NAME}}-http.service={{NAME}}

      # ── Service definition ─────────────────────────────────────────────
      - traefik.http.services.{{NAME}}.loadbalancer.server.port={{PORT}}

networks:
  coolify:
    external: true
