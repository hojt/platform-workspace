# .claude

This directory exists so that the agent container can mount an
agent-only tmpfs here. Claude Code writes local settings and other
state to this directory. In the agent container, that state is
discarded when the container stops and never reaches the host.

Permissions are enforced through managed settings in the agent image,
so nothing written here can change them.

See ADR-0010 in hojt/homelab.
