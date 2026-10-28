# 1Panel Website API

Use this reference for the normal `xxx.linktion.cn` publication step after the local service and FRP TCP proxy are healthy.

## Authentication

- Base URL: `https://panel.linktion.cn/api/v2`
- Keep the API Key outside files and command arguments. The bundled client reads `ONEPANEL_API_KEY` from the environment.
- Send `1Panel-Timestamp` as the current Unix timestamp in seconds.
- Prefer HMAC-SHA256: `hmac_sha256(API-Key, "1panel:" + timestamp)`.
- This panel currently accepts the legacy signature: `md5("1panel" + API-Key + timestamp)`. The client tries HMAC first and retries MD5 only after an authentication failure.
- Keep the client and server clocks synchronized. Respect the API Key's IP whitelist and expiry.
- The Swagger JSON requires a logged-in browser session; API Key authentication is for `/api/v2` endpoints.

Never print the API Key, generated signature, certificate, private key, authorization fields, or complete unredacted API responses.

## Inspect before mutation

Use `scripts/onepanel-api.py` for signed requests. Read-only examples:

```bash
scripts/onepanel-api.py GET /websites/list
scripts/onepanel-api.py POST /websites/search --data '{"page":1,"pageSize":100,"name":"","orderBy":"created_at","order":"descending","websiteGroupId":0}'
scripts/onepanel-api.py POST /websites/ssl/search --data '{"page":1,"pageSize":100,"acmeAccountID":""}'
scripts/onepanel-api.py GET /websites/<website-id>/https
scripts/onepanel-api.py POST /websites/proxies --data '{"id":<website-id>}'
```

The client redacts sensitive response fields. Confirm that the requested primary domain does not already exist, find the current Website group, and locate the auto-renewing certificate covering `*.linktion.cn`.

Website groups come from `POST /groups/search --data '{"type":"website"}'`. `GET /websites/groups` returns a 500 and `GET /groups` a 404 on this panel — do not try them. `/groups/search` is read-only and whitelisted in `scripts/onepanel-api.py`, so it needs no `--allow-write`.

Invoke the client as `python3 scripts/onepanel-api.py …` (or `bash` for shell scripts); skill installation may drop the executable bit.

## Create the proxy Website

Creating or changing a Website is an external mutation. An explicit request to deploy and bind the named domain authorizes creating that Website and enabling HTTPS; do not ask for duplicate confirmation. Use `--allow-write` only after local and FRP validation and after resolving the exact domain and remote port. Require separate approval before deleting an unrelated Website, changing shared DNS, or deleting a shared certificate.

Call `POST /websites` with a payload based on:

```json
{
  "type": "proxy",
  "alias": "<service>.linktion.cn",
  "remark": "",
  "proxy": "http://127.0.0.1:<frp-remote-port>",
  "webSiteGroupID": <current-group-id>,
  "IPV6": false,
  "appType": "installed",
  "appInstallID": 0,
  "domains": [{ "domain": "<service>.linktion.cn", "port": 80, "ssl": false }]
}
```

> Verified 2026-10-06 against the live panel: the current 1Panel v2 `WebsiteCreate` DTO no
> longer accepts `primaryDomain`, `otherDomains`, `proxyType`, or `port`; the domain goes in
> the `domains` array (`WebsiteDomain { domain, port, ssl }`), and sending the old shape
> returns `code: 500` with an **empty message**. Do not guess field-name variants — fetch the
> DTO for the installed version from source and adapt the payload to it:
>
> ```bash
> gh api repos/1Panel-dev/1Panel/contents/agent/app/dto/request/website.go --jq .content | base64 -d
> ```
>
> Older panel builds used the `primaryDomain` form; the DTO is the authority for whichever
> version is installed.

Query `/websites/list` afterward and resolve the new Website ID by exact `primaryDomain`; do not assume a returned or sequential ID. Inspect `/websites/proxies` and verify the root rule is enabled, matches `/`, uses the intended upstream, and keeps `proxyHost` as `$host` unless the application requires another Host.

## Enable HTTPS

1. GET `/websites/<website-id>/https` and preserve its current cipher/default fields.
2. Find the existing auto-renewing SSL record whose primary domain is `*.linktion.cn`; never hardcode its ID.
3. POST `/websites/<website-id>/https` with the exact camel-case field `websiteId` (not `websiteID`), `enable: true`, the matching `websiteSSLId`, `type: "existed"`, `httpConfig: "HTTPToHTTPS"`, `SSLProtocol: ["TLSv1.3", "TLSv1.2"]`, and the current safe defaults such as `algorithm` and `hsts`:

```json
{
  "websiteId": <website-id>,
  "enable": true,
  "websiteSSLId": <wildcard-ssl-id>,
  "type": "existed",
  "privateKey": "",
  "certificate": "",
  "privateKeyPath": "",
  "certificatePath": "",
  "importType": "paste",
  "httpConfig": "HTTPToHTTPS",
  "SSLProtocol": ["TLSv1.3", "TLSv1.2"],
  "algorithm": "<value-preserved-from-current-config>",
  "hsts": true
}
```

4. GET the HTTPS configuration again, then verify the public certificate and redirect with `curl` or `openssl s_client`.

Do not request a new certificate if the wildcard already covers the hostname. Do not transmit or log private-key/certificate bodies.

## Validate and roll back

Validate DNS, HTTP redirect, HTTPS status, certificate hostname, proxy upstream, application login/API, WebSocket, and uploads. A successful Website creation does not prove the FRP target is healthy.

If Website or HTTPS creation fails, keep the working FRP proxy while diagnosing unless it creates exposure. For a full rollback, remove or disable the 1Panel Website first, then remove the FRP block and restart only the primary frpc client, then stop the local service if requested. Never delete the shared wildcard certificate.
