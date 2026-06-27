# coordination_server

A standalone Swift HTTP service that brokers policy-rejected smart-account
calls between the autonomous reference agent and the OpenZeppelin
smart-account demo app (iOS, macOS, and web).

The agent posts smart-account calls that its on-chain policy rejected; the demo
app polls them, lets the user approve or reject each one, and reports the
outcome back. The server is the message channel only: it stores requests and
their resolution, never any signing material. `args` are opaque base64 strings
stored and echoed verbatim, so the server has no dependency on the Stellar SDK.

## Requirements

- Swift 6.0+ (macOS 15+)
- Hummingbird 2.x (resolved automatically)

## Build and run

```sh
cd coordination_server
swift build

# A bearer token is mandatory. The server refuses to start without one.
swift run coordination-server --token dev-token-change-me
```

For local development you can use the token `dev-token-change-me`. Use a
strong, secret value in any shared or deployed environment.

### Configuration

| Setting | Env var              | CLI flag          | Default   |
|---------|----------------------|-------------------|-----------|
| Port    | `PORT`               | `--port <n>`      | `8787`    |
| Token   | `COORDINATION_TOKEN` | `--token <s>`     | required  |
| Store   | `COORDINATION_STORE` | `--store <path>`  | in-memory |

CLI flags take precedence over environment variables (each flag also accepts
the `--flag=value` form). The server binds `0.0.0.0` so it is reachable from
simulators, devices, and browsers on the LAN. A configuration error exits with
code 64 (`EX_USAGE`).

With `--store` set, the request set is loaded on start (if the file exists) and
written atomically after every mutation, so requests survive a restart. Without
it, state is in-memory only.

```sh
# Persisted, custom port, token via flag:
swift run coordination-server --token dev-token-change-me --port 8787 --store ./requests.json
```

The server logs one line per request to stdout.

## Authentication

Every `/requests*` route requires `Authorization: Bearer <token>`. `/health`
and CORS preflight (`OPTIONS`) are exempt. A missing or invalid token returns
`401`; the token comparison is constant-time. CORS is enabled for all origins
so the web build can poll the service from a browser.

## Request model

The canonical request object (all fields always present; nullable fields are
`null` until set):

```json
{
  "id":           "string  (uuid v4, server-assigned)",
  "smartAccount": "string  (C-address of the smart account)",
  "target":       "string  (C-address the agent tried to call)",
  "targetFn":     "string  (e.g. \"transfer\")",
  "args":         ["string (base64-encoded XdrSCVal entries, opaque to the server)"],
  "amount":       "string  (display-only; empty string when not supplied)",
  "reason":       3016,
  "status":       "pending | approved | rejected",
  "createdAt":    1782485036185,
  "resolvedAt":   null,
  "resultHash":   null,
  "note":         null
}
```

`args` are stored and returned verbatim so the inbox can rebuild the original
call exactly. The server never inspects them.

## Endpoints

| Method | Path                       | Auth | Description                                  |
|--------|----------------------------|------|----------------------------------------------|
| GET    | `/health`                  | no   | Liveness check (`{"status":"ok"}`).          |
| POST   | `/requests`                | yes  | Agent posts a rejected call. Returns `201`.  |
| GET    | `/requests`                | yes  | List all requests, newest first.             |
| GET    | `/requests?status=<s>`     | yes  | List filtered by `pending`/`approved`/`rejected`. |
| GET    | `/requests/{id}`           | yes  | Fetch one request (poll its status).         |
| POST   | `/requests/{id}/approve`   | yes  | Approve a pending request.                    |
| POST   | `/requests/{id}/reject`    | yes  | Reject a pending request.                     |

### Status codes

- `200` success, `201` created.
- `400` malformed or invalid body / unknown status filter.
- `401` missing or invalid bearer token.
- `404` unknown request id.
- `409` request is already resolved (a second approve/reject).
- `500` unexpected server error.

All error responses are JSON of the shape `{ "error": "..." }`.

### POST /requests

Body (server-assigned fields are ignored if sent):

```json
{
  "smartAccount": "C...",
  "target":       "C...",
  "targetFn":     "transfer",
  "args":         ["AAAA", "BBBB"],
  "amount":       "10.5",
  "reason":       3016
}
```

Required: `smartAccount`, `target`, `targetFn` (non-empty strings), `args`
(list of strings), `reason` (integer). `amount` is an optional string and
defaults to `""`. Returns `201` with the full created object (`status` is
`pending`).

### POST /requests/{id}/approve

Body: `{ "resultHash": "<tx-or-result-hash>" }` (non-empty string, required).
Sets `status` to `approved`, fills `resolvedAt` and `resultHash`. Returns `200`
with the updated object; `404` if unknown; `409` if already resolved.

### POST /requests/{id}/reject

Body: `{ "note": "<optional reason>" }` (the body may be empty). Sets `status`
to `rejected`, fills `resolvedAt`, and stores `note` when provided. Returns
`200`; `404`; `409` if already resolved.

## Project layout

```
coordination_server/
  Sources/coordination-server/        executable entry point: config, store load, serve
  Sources/CoordinationServerCore/     library used by the executable and tests
    Errors.swift                      typed domain errors (validation/not-found/conflict/config)
    JSONValidation.swift              field-level validators over decoded JSON
    Models.swift                      request model, input validation, status enum
    RequestStore.swift                in-memory store actor + atomic JSON persistence
    ServerConfig.swift                CLI/env configuration
    Middleware.swift                  CORS, bearer auth, error mapping, request logging
    HTTPResponses.swift               JSON response helpers
    CoordinationRouter.swift          routes + application assembly
  Tests/CoordinationServerCoreTests/  store, HTTP, and config suites
```

## Tests

```sh
swift test   # store, HTTP, and config suites
```
