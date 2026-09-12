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

## Host layout

The workspace expects the repositories to exist as siblings on the host:

```text
~/src/lab/
├── platform-workspace/
├── homelab/
├── local-platform/
├── local-environments/
└── example-app/
```

Only the three platform repositories are mounted into this workspace.
`example-app` remains outside it.

The `repos/` directory in this repository is only the mount point used inside
the development environments. Its mounted contents are intentionally ignored by
the `platform-workspace` Git repository.

## Container workspace layout

Both the developer and coding-agent environments present the same repository
layout:

```text
/workspace/
├── README.md
├── AGENTS.md
├── dev.sh
├── agent.sh
└── repos/
    ├── homelab/
    ├── local-platform/
    └── local-environments/
```

`/workspace` is the `platform-workspace` repository itself. The three
repositories under `/workspace/repos/` are bind mounts of the sibling
repositories on the host.

Each mounted repository retains its own independent Git state and history.

## Development environments

This repository provides two separate devcontainer environments.

### Developer environment

Start or enter the primary developer environment with:

```bash
./dev.sh
```

Rebuild it with:

```bash
./dev.sh rebuild
```

Open an additional shell in an already running developer container with:

```bash
./dev.sh shell
```

The developer environment is intentionally capable of operating the local
platform. It has access to capabilities such as:

- the host Podman socket
- the host Kubernetes configuration
- host networking
- the developer Git configuration
- the developer Neovim configuration

This environment is for the human developer.

### Coding-agent environment

Start OpenCode in the contained coding-agent environment with:

```bash
./agent.sh
```

Rebuild it with:

```bash
./agent.sh rebuild
```

Open a diagnostic shell in the coding-agent environment with:

```bash
./agent.sh shell
```

The coding-agent environment has read/write access to the workspace repositories
but intentionally does not receive the privileged host capabilities available
to the developer environment.

In particular, the agent environment is expected not to expose:

- the host Podman socket
- the host Kubernetes configuration
- the host Git configuration
- container-runtime connection environment variables

`agent.sh` verifies both the expected repository mounts and these containment
properties before starting OpenCode or an agent shell.

Platform tools such as `kubectl`, `kind`, or `podman` may still exist as
binaries inside the image. Containment is based on withholding the credentials,
sockets, networking, and other capability channels that would grant access to
the host or live cluster.

This still allows useful local validation such as manifest rendering without
granting the coding agent control over the local platform.

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
