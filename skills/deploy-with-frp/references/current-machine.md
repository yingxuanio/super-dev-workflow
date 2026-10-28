# Current machine

Snapshot verified on 2026-08-08. Refresh it with `../scripts/inspect-host.sh` before acting.

## Host and runtimes

- Host: Apple Silicon Mac mini running macOS.
- Docker: `/usr/local/bin/docker`; Docker Compose v2 is available as `docker compose`.
- frpc: `/opt/homebrew/bin/frpc` (Homebrew installation).
- Use `127.0.0.1:<port>` for local FRP targets unless a service intentionally lives in OrbStack DNS or on another host.

## FRP clients

Two independent frpc processes run concurrently. Never use `pkill frpc` or restart both as a shortcut.

### Primary domestic tunnel

- Server: `frp.linktion.cn:7000`
- Config: `/opt/homebrew/etc/frp/frpc.toml`
- LaunchAgent label: `homebrew.mxcl.frpc`
- Manage with: `brew services info frpc` and `brew services restart frpc`
- Use for raw `frp.linktion.cn:<remotePort>` publication and services whose public domain is routed through the domestic endpoint.

### Overseas tunnel

- Config: `/opt/homebrew/etc/frp/frpc-new.toml`
- LaunchAgent label: `homebrew.mxcl.frpc-new`
- It is a custom LaunchAgent, not an installed Homebrew formula named `frpc-new`.
- Use only for the existing overseas/crossmind.io routing or when the user explicitly chooses it.

## Safe configuration procedure

1. Resolve the running process and its `-c` path with `ps` or the inspection script.
2. Create a timestamped backup beside the config.
3. Add one `[[proxies]]` block without reformatting or replacing unrelated blocks.
4. Validate with `/opt/homebrew/bin/frpc verify -c /opt/homebrew/etc/frp/frpc.toml`.
5. Restart only `frpc` through Homebrew and confirm the new process uses the same config.
6. Check registration and public reachability. Restore the backup and restart the same service if registration or application checks fail.

The config contains an authentication token. Read or edit it only when necessary and always redact it from tool output and responses.

## Existing deployment pattern

Multica demonstrates the preferred pattern:

- Containers communicate on a private Compose network.
- A local Nginx gateway publishes one loopback port.
- The primary frpc config maps one TCP remote port to that local gateway.
- A separate public reverse proxy/DNS layer provides the custom domain and HTTPS.
- Nginx routes page traffic to the frontend and API/WebSocket traffic directly to the Go backend.

The public reverse-proxy layer is normally a 1Panel Website on `panel.linktion.cn`:

- API base: `https://panel.linktion.cn/api/v2`
- API documentation: `https://panel.linktion.cn/1panel/swagger/doc.json` (requires a panel login session)
- Normal Website type: `proxy`
- Normal upstream: `http://127.0.0.1:<frp-remote-port>` from the 1Panel/frps host
- Normal certificate: the existing auto-renewing `*.linktion.cn` certificate
- Normal HTTPS mode: HTTP-to-HTTPS with TLS 1.2 and TLS 1.3

Multica currently follows this pattern with its FRP remote port. Treat Website IDs, certificate IDs, group IDs, and ports as mutable: query them at execution time instead of copying current numeric IDs.

Do not assume its current ports are reusable. Inspect live listeners, Compose projects, and all `remotePort` entries first.
