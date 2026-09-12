# platform-workspace

Development workspace for the homelab platform.

## Purpose

This repository provides a common development workspace for the repositories
that together define, implement, and operate the homelab platform.

The workspace exists so that a human developer or coding agent can reason about
platform architecture, implementation, and desired environment state together
without merging their responsibilities into a single repository.

The repositories remain independently versioned Git repositories with distinct
ownership boundaries.

## Workspace repositories

The platform workspace is composed of:

- `homelab` — platform architecture, principles, and architecture decision records
- `local-platform` — local platform implementation, bootstrap, and lifecycle
- `local-environments` — GitOps desired state for workloads and environments

These repositories are developed together when a change genuinely spans more
than one responsibility.

They are not combined into a monorepo and do not share Git history.

`example-app` is not part of the platform workspace. Applications use their own
application workspaces and consume the platform through documented contracts.

## Repository responsibilities

### `homelab`

Owns the platform-level context and rationale:

- architecture
- design principles
- architecture decision records
- cross-repository concepts and boundaries

### `local-platform`

Owns implementation and lifecycle of the local Kubernetes platform:

- cluster bootstrap and teardown
- platform services
- local development platform plumbing
- platform lifecycle automation

### `local-environments`

Owns desired Kubernetes environment state:

- Argo CD applications
- application deployments
- services and routes
- environment-specific configuration
- other declarative workload state

Application source code and build tooling do not belong here.

## Development model

The workspace follows a few core principles:

- repository boundaries represent responsibility and ownership boundaries;
- a development workspace may span several repositories when they must be
  understood together;
- repository boundaries must not be weakened merely because the repositories
  are visible in the same workspace;
- prefer the smallest useful change;
- avoid speculative abstractions;
- keep architecture, platform implementation, and desired state in their
  respective repositories.

A single platform change may legitimately require coordinated changes in more
than one repository. Each repository should still contain only the part of the
change that belongs to its responsibility.

## Workspace layout

The intended development environment presents the workspace approximately as:

```text
/workspace/
├── platform-workspace/
├── homelab/
├── local-platform/
└── local-environments/
```

The exact physical layout on the host may differ. The component repositories
remain separate Git repositories.

## Development environment

This repository will provide shared development tooling for working across the
platform repositories, including:

- a developer devcontainer
- a coding-agent devcontainer
- repository-level Task commands where useful
- workspace instructions and documentation

The developer and coding-agent environments may intentionally have different
capabilities.

The coding-agent environment should be contained and should not automatically
receive access to privileged host or cluster capabilities merely because the
developer environment requires them.

## Git

Every repository in the workspace has independent Git state.

The human developer owns staging, commits, tags, pushes, and history-changing
operations in every repository.

Workspace tooling must not treat the repositories as a single Git repository.

## Architecture

This workspace is an implementation of the distinction between:

- Git repository
- development workspace
- deployment unit

Those boundaries are related but are not the same thing.

The platform workspace is intentionally broader than any one platform
repository because architecture, implementation, and desired state frequently
need to be reasoned about together while remaining separately owned.
