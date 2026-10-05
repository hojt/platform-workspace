# .opencode

This directory exists so that the agent container can mount an
agent-only tmpfs here. Opencode writes plugin dependencies and other
state to this directory at startup. In the agent container, that state
is discarded when the container stops and never reaches the host.

See ADR-0010 in hojt/homelab.
