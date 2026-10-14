name: ci

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

# Workload-specific CI lives downstream — this is the minimum skeleton.
# The skill leaves the actual lint/test/build commands as TODOs because
# they're stack-specific; fill them in after the first commit.

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      # TODO: set up {{STACK}} toolchain
      # TODO: install deps
      # TODO: run lint
      # TODO: run tests
      # TODO: build

      - name: Smoke-check Dockerfile and compose
        run: |
          docker build -t {{NAME}}:ci .
          # No deploy here — Coolify handles deploys via its own webhook.
