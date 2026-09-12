# Agent Instructions

This repository defines the development workspace for the homelab platform.

The workspace contains multiple independent Git repositories with distinct
responsibilities. Visibility across repositories is provided so that platform
changes can be understood as a whole, not so that repository boundaries can be
ignored.

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

## Development environments

The workspace provides separate environments for the human developer and the
coding agent.

The developer environment may include capabilities required to operate and
inspect the local platform.

The coding-agent environment should receive only the capabilities required to
inspect, edit, and validate repository content.

Do not assume that capabilities available to the developer environment are
available or appropriate for the coding-agent environment.

### Agent containment

The development environment is intentionally designed to contain the coding
agent and limit its blast radius.

Do not attempt to bypass, weaken, or escape this containment.

If you notice configuration or architectural issues that could unintentionally
grant the agent broader access or capabilities than intended, point them out
clearly so they can be reviewed by the human developer.

Do not add privileged host, container-runtime, Kubernetes-cluster, or similar
access to the agent environment unless the human developer explicitly requests
it for a concrete reason.

## Cluster state and GitOps

Git is the source of truth for desired environment state.

Do not make direct cluster changes as a substitute for changing
`local-environments`.

If cluster access is available for validation, use it only to inspect or verify
the effect of repository-defined state unless the human developer explicitly
requests an operational action.

Do not silently reconcile configuration by modifying live resources outside
Git.

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
