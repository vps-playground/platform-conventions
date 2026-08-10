set dotenv-load := true

# List recipes.
default:
    @just --list

# Stack-specific dev / test / build / lint recipes are appended by the
# stack overlay. The recipes below are universal across all stacks.

# Preflight runs everything that must be green before a deploy.
preflight: lint test build

# Push to origin/main; Coolify auto-deploys via GitHub webhook.
deploy: preflight
    @echo ""
    @echo "→ pushing main to origin (Coolify will auto-deploy)..."
    git push origin main
    @echo ""
    @echo "✓ pushed. Watch Coolify UI → Deployments for build status."

# Verify the deployed /healthz endpoint (ADR-0002).
healthz:
    @curl -fsS https://{{HOSTNAME}}/healthz && echo " ← healthz ok" || (echo "✗ healthz failed" && exit 1)
