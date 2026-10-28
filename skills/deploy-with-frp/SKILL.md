---
name: deploy-with-frp
description: Choose the appropriate hosting target, then deploy, update, troubleshoot, or remove complex services on Ivan's current Mac mini through frpc and 1Panel. Use to decide between Mac mini + FRP + 1Panel for multi-component or stateful systems and Cloudflare Pages or Vercel for lightweight websites and frontend-only projects; also use for Docker Compose or native-service deployment, local port allocation, frp.linktion.cn publication, xxx.linktion.cn reverse proxies, wildcard HTTPS, WebSockets, uploads, health checks, diagnosis, and rollback.
---

# Deploy with FRP

Deploy services on the current Mac, expose only the intended entrypoint through the existing FRP client, and verify every hop before declaring success.

## Select the deployment target first

Use Mac mini + FRP + 1Panel for systems that benefit from this machine's higher capacity or require one or more of:

- Multiple cooperating services or containers.
- A dedicated database, cache, queue, object store, or persistent volume.
- Background workers, daemons, agents, WebSockets, or other long-lived processes.
- Custom networking, native binaries, substantial CPU/RAM, or access to private/local dependencies.
- An example architecture such as Multica, where frontend, backend, database, gateway, and runtime components operate together.

Recommend Cloudflare Pages or Vercel instead for static sites, landing pages, documentation, SPAs, lightweight webpages, and frontend-only projects. Also prefer them for small serverless/edge-compatible applications that do not need durable local state or long-running processes. Check the providers' current official framework and runtime support before choosing between them.

Do not allocate a Mac port, FRP remote port, or 1Panel Website for a lightweight project unless the user explicitly prefers self-hosting after seeing the tradeoff. A direct request to deploy on this Mac overrides the recommendation while keeping all safety checks.

Use a hybrid only when justified: host the frontend on Cloudflare Pages or Vercel and keep the stateful backend on the Mac. Account for CORS, cookie domains, authentication callbacks, API URLs, and separate deployment lifecycles before choosing it.

## Load the machine context

Read [references/current-machine.md](references/current-machine.md) before changing deployment or FRP configuration. Run `scripts/inspect-host.sh` to refresh live state because ports, containers, and service PIDs can change.

Read [references/routing-patterns.md](references/routing-patterns.md) when the service has a frontend plus API/WebSocket, needs a custom domain or HTTPS, accepts large uploads, or requires a choice between TCP and HTTP FRP proxies.

Read [references/1panel-api.md](references/1panel-api.md) whenever creating, inspecting, updating, or removing an `xxx.linktion.cn` Website or its HTTPS configuration through 1Panel.

## Follow the workflow

1. Apply the deployment-target decision above. If a managed frontend platform is the better fit, recommend it and stop the Mac/FRP workflow unless the user chooses self-hosting.
2. Inspect repository instructions, existing Compose files, environment templates, health endpoints, and required persistent volumes.
3. Run the read-only host inspection script. Resolve port collisions before creating or starting anything.
4. Choose one private local entrypoint. Prefer Docker Compose and bind the published port to `127.0.0.1`; do not expose databases, caches, Docker sockets, admin panels, SSH, or VNC unless the user explicitly requests and secures them.
5. Preserve existing user configuration. Keep secrets in the service's ignored `.env` or secret store; never place tokens, passwords, private keys, or full environment files in this Skill, tracked files, logs, or the final response.
6. Start the service locally and prove its health on the selected loopback port before touching FRP.
7. Select the correct FRP client. Default public access via `frp.linktion.cn` to the primary domestic config. Do not edit or restart the separate overseas tunnel unless the requested hostname belongs there.
8. Inspect all existing proxy names and remote ports. Do not trust raw TCP probes (`nc -z`, socket connect) against public hosts from this machine: DNS resolves public names into a local fake-IP/TUN proxy (198.18.0.0/15 answers), so connections to ANY port succeed and a probe proves nothing in either direction. Calibrate with real requests instead: `curl -s -m 6 http://frp.linktion.cn:<candidate>/` returns an empty reply on an unregistered port and a real status on a registered one — compare against a known-in-use port. `frpc start proxy success` in the log plus an actual HTTP response is authoritative. Use a unique, descriptive proxy name.
9. Back up the exact FRP config, edit only the required proxy block, then run `/opt/homebrew/bin/frpc verify -c <config>`. If validation fails, restore the backup and do not restart.
10. Restart only the owning LaunchAgent. For the primary Homebrew service use `brew services restart frpc`; confirm its PID and config path afterward. Never kill every `frpc` process because two independent clients run here.
11. For the normal `xxx.linktion.cn` deployment, use the 1Panel Website API at `https://panel.linktion.cn/api/v2` to create a `proxy` Website whose upstream is `http://127.0.0.1:<frp-remote-port>`. Check for an existing domain first and preserve unrelated Websites.
12. Reuse the existing auto-renewing `*.linktion.cn` certificate through the Website HTTPS endpoint. Read current Website HTTPS defaults first, then enable TLS 1.2/1.3 and HTTP-to-HTTPS. Never download, print, or store certificate private-key material.
13. Validate each hop: local health, local gateway, FRP host and port, 1Panel Website proxy, public hostname and HTTPS, API, WebSocket, and a realistic upload when applicable. Correlate gateway, frontend, backend, frpc, and 1Panel logs by timestamp and request path.
14. Report the selected hosting target and rationale. For Mac deployments also report the local port, FRP proxy name and remote port, 1Panel Website ID, public URL, config paths changed, verification performed, and rollback method. Do not report secret values.

## Apply routing safeguards

- Use one same-origin gateway for applications with a web UI and API.
- Route `/api/` directly to the backend when a frontend framework proxy has body-size or timeout limits.
- Forward `Upgrade` and `Connection` headers for every actual WebSocket path, including WebSockets nested under `/api/`.
- Keep Nginx request buffering enabled for slow public uploads when the backend has a request read timeout.
- Set the gateway body limit slightly above the backend's enforced maximum to allow multipart framing. Keep the backend as the final authority.
- Forward `Host`, `X-Real-IP`, `X-Forwarded-For`, and `X-Forwarded-Proto`.
- Bind the gateway locally and expose only it through FRP; keep backend and database ports internal to the Compose network.

Use [assets/frpc-tcp-proxy.toml](assets/frpc-tcp-proxy.toml) and [assets/nginx-same-origin.conf](assets/nginx-same-origin.conf) as starting templates. Replace every angle-bracket placeholder and adapt paths to the application; do not copy a template blindly.

## Diagnose failures by layer

- Connection refused locally: service, bind address, container network, or health problem.
- FRP proxy registration error: duplicate name/remote port, invalid config, authentication, or frps policy.
- Public 502/504: remote reverse proxy cannot reach the FRP listener, or the local upstream is unhealthy.
- Public 413: body-size limit at the remote proxy, local gateway, frontend proxy, or backend.
- Public 500 during upload: inspect frontend and backend logs; framework proxies may truncate or reset large bodies even after Nginx accepts them.
- WebSocket 400 or repeated reconnects: upgrade headers were lost or the WebSocket path is routed through the wrong upstream.
- HTTP works but HTTPS fails: DNS, certificate, SNI, or remote reverse-proxy configuration—not the local container.
- Domain returns a 1Panel default page or 404: Website record, primary domain, proxy root rule, or wildcard DNS mismatch.

Prefer a targeted configuration reload over a full deployment restart. Keep the last known-good backup until public verification succeeds.
