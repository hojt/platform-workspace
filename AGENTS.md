# Agent Instructions

This repository defines the development workspace for the homelab platform.

The workspace contains multiple independent Git repositories with distinct
responsibilities. Visibility across repositories is provided so that platform
changes can be understood as a whole, not so that repository boundaries can be
ignored.

## Workspace layout

The coding-agent environment presents:

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

`/workspace` is the `platform-workspace` repository.

The repositories under `/workspace/repos/` are independent Git repositories
bind-mounted into the workspace.

## Repository responsibilities

### `homelab`

Owns:

- platform architecture
- design principles
- architecture decision records
- cross-repository rationale and boundaries

Use this repository for the reasoning and documentation behind platform-level
decisions.

### `local-platform`

Owns:

- local Kubernetes platform implementation
- platform bootstrap and teardown
- platform services
- platform lifecycle automation

Do not move workload desired state into this repository.

### `local-environments`

Owns:

- GitOps desired state
- Argo CD applications
- workload deployments
- services and routes
- environment-specific Kubernetes configuration

Do not move platform bootstrap or application source code into this repository.

## Workspace boundaries

Respect repository ownership boundaries at all times.

A task may require changes in more than one repository. When that happens, make
the part of the change that belongs to each responsibility in the appropriate
repository.

Do not move responsibilities between repositories merely because all
repositories are visible in the same workspace.

Do not copy architecture documentation into implementation repositories solely
to make it locally visible. Prefer the authoritative source in `homelab`.

Application source repositories such as `example-app` are outside this platform
workspace unless the human developer explicitly includes them for a concrete
task.

## Development

Use existing repository Task commands as the preferred development interface
when available.

Prefer the smallest useful implementation.

Validate changes using the tooling available inside the workspace before
considering work complete.

Do not introduce abstractions, shared tooling, new repository structure, or
cross-repository coupling for speculative future requirements.

When a change spans repositories, validate each affected repository separately
as well as any relevant cross-repository assumptions.

Static validation that does not require privileged host or cluster access is
appropriate. For example, rendering Kubernetes manifests locally is compatible
with the intended agent environment.

## Development environments

The human developer and coding agent use separate environments.

The developer environment may include capabilities required to operate and
inspect the local platform.

The coding-agent environment intentionally receives a narrower capability set.
It has read/write access to the workspace repositories but must not assume it has
the privileges available to the developer environment.

The presence of tools such as `kubectl`, `kind`, or `podman` does not imply that
the agent should have access to the host container runtime or Kubernetes
cluster.

### Agent containment

The development environment is intentionally designed to contain the coding
agent and limit its blast radius.

Do not attempt to bypass, weaken, or escape this containment.

The expected agent environment does not expose:

- the host Podman socket
- the host Kubernetes configuration
- the host Git configuration
- container-runtime connection environment variables

`agent.sh` verifies these containment expectations before starting OpenCode or
an agent shell.

Do not modify the workspace configuration to bypass these checks.

If you notice configuration or architectural issues that could unintentionally
grant the agent broader access or capabilities than intended, point them out
clearly so they can be reviewed by the human developer.

Do not add privileged host, container-runtime, Kubernetes-cluster, host-network,
or similar access to the agent environment unless the human developer
explicitly requests it for a concrete reason.

## Cluster state and GitOps

Git is the source of truth for desired environment state.

Do not make direct cluster changes as a substitute for changing
`local-environments`.

The coding-agent environment is not intended to have credentials or runtime
access for operating the live local cluster.

If cluster access is ever explicitly provided for a concrete task, use it only
within the scope requested by the human developer and do not silently reconcile
configuration by modifying live resources outside Git.

## Git

Each repository has independent Git state.

Never create Git commits.

Never rewrite Git history under any circumstances.

The human developer always owns staging, commits, tags, and pushes.

Do not perform Git operations in one repository merely to make another
repository appear clean or synchronized.

## Architecture

Prefer existing architecture decisions and repository conventions over
inventing new ones.

Use `homelab` as the authoritative source for platform-level architecture and
decision rationale.

If implementation reality conflicts with documented architecture, point out the
conflict rather than silently changing one side to match the other.

Keep repository boundaries aligned with demonstrated responsibility and
ownership needs.

A development workspace may span repositories without turning those repositories
into a single ownership or release unit.
