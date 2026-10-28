# Routing patterns

## Select the hosting class

Treat the Mac + FRP + 1Panel path as infrastructure for complex or stateful systems, not the default for every webpage. Prefer Cloudflare Pages or Vercel for static and frontend-only workloads. Use this reference only after the project genuinely needs the Mac path or the user explicitly chooses self-hosting.

## Choose an FRP proxy type

Use a TCP proxy when publishing `frp.linktion.cn:<remotePort>` or when a separate remote reverse proxy terminates TLS and forwards to that port. It is simple, preserves arbitrary protocols, and matches the primary tunnel's common pattern.

Use an HTTP/HTTPS FRP proxy only when the target frps is configured with HTTP/HTTPS vhost ports and the requested domain is managed directly by frps. Confirm server capabilities before adding `customDomains`; do not infer support from the local binary.

## Choose a local topology

For a single HTTP service, map FRP directly to its loopback-bound port.

For a frontend plus backend, map FRP to a local gateway:

```text
public domain or frp port -> frps -> frpc -> loopback gateway
                                             |-> frontend
                                             |-> /api backend
                                             `-> WebSocket backend
```

Keep PostgreSQL, Redis, object storage, and internal admin endpoints off published host ports whenever possible.

## Custom domains and HTTPS

A public URL requires three independently verified pieces:

1. DNS resolves the hostname to the public 1Panel/TLS endpoint.
2. A 1Panel `proxy` Website owns the hostname and forwards to `http://127.0.0.1:<frp-remote-port>` on the frps host.
3. frps/frpc forwards the connection to the healthy local gateway.

Verify with `dig` or `dscacheutil`, `curl -vI https://<domain>`, and the local/remote service logs. Preserve the original Host header when the application uses host-based routing.

For `xxx.linktion.cn`, prefer the existing auto-renewing wildcard certificate. Do not issue a redundant certificate unless the wildcard does not cover the requested hostname.

## Uploads and long requests

Find every limit in the path: public proxy, local Nginx, frontend framework, backend request reader, and object store. Set infrastructure limits just above the application's explicit maximum.

For large multipart uploads, leave Nginx request buffering enabled when the public client may be slow. Direct `/api/` to the backend if Next.js or another frontend proxy imposes a smaller body cap or resets the upstream. Validate with a representative authenticated upload—not only a tiny health request.

## WebSockets

Inventory every WebSocket path; applications may use both `/ws` and paths such as `/api/daemon/ws`. Route those paths to the WebSocket server and forward the upgrade headers. A normal HTTP 200 test does not prove WebSocket functionality; confirm a 101 upgrade or a backend “connected” event.

## Validation order

1. Container/process status and health.
2. Direct local service URL.
3. Direct local gateway URL with the expected Host header.
4. `frp.linktion.cn:<remotePort>` when protocol allows. Raw TCP connect probes are meaningless here (local fake-IP/TUN proxy accepts any port): an unregistered port gives curl an empty reply where a registered one gives a real status — compare the two before concluding anything.
5. Public hostname over HTTPS.
6. Login/session, API call, WebSocket, and representative upload.
7. Fresh logs with no new 4xx/5xx or reconnect loop.

Use exact timestamps and paths when correlating logs. An outer 500 can correspond to an inner 400 or reset, so inspect every proxy layer.
