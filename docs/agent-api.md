# The Agent API

`POST /agent` answers a natural-language question about the user's Zwiki knowledge
base, and can edit it. Server-side, it runs a tool loop: Claude searches and reads
the user's nodes, optionally writes to them, then returns a prose answer plus a
record of what it did.

This document is for building a client against it. It assumes no knowledge of the
Rails app.

## Domain model in one paragraph

A Zwiki is a graph of **nodes**. A node is a markdown document. Its `name` is taken
from its first `# Title` line. Its identifier is a **`short_id`** — a compact string
like `ABC123`. Nodes link to each other inline with `[Link Text](short_id)` and embed
each other with `{Text}(short_id)`. Journal entries are nodes named like
`Fri Nov 25 2022`.

## Authentication

Every request needs an `Authorization` header containing the **raw token**:

```
Authorization: kQ8rTvN2pXmLw...
```

**Not** `Bearer <token>`. The server compares the header value against stored tokens
directly, so a `Bearer ` prefix will fail authentication.

Get a token with `POST /login`:

```
POST /login
{ "name": "...", "password": "..." }

200 → { "token": "kQ8r...", "expires_at": "2026-07-30T12:00:00Z" }
401 → "ILUVU"
```

Note it authenticates on **`name`, not email**. The returned token is `full_access`
and expires in 6 months.

There are two token types, and the distinction matters for this endpoint:

| Type | Obtained via | Agent can |
|---|---|---|
| `full_access` | `POST /login` | read **and write** nodes |
| `read_only` | `POST /tokens/read_only` | read only |

## Request

```
POST /agent
Authorization: <token>
Content-Type: application/json

{ "query": "What have I been writing about recently?" }
```

`query` is the only parameter. It is free-form natural language — there is no query
syntax to learn or escape. A whitespace-only query is rejected.

## Response

```jsonc
{
  "answer": "Your recent writing clusters on career strategy and language learning…",

  // Every tool the agent invoked, in order. Useful for a "show your work" trace.
  "tool_calls": [
    { "name": "search_nodes",   "input": { "query": "language learning" } },
    { "name": "read_node",      "input": { "short_id": "ABC123" } },
    { "name": "append_to_node", "input": { "short_id": "Reading List", "text": "\n- Snow Crash" } },
    // A failed tool call carries an `error` key and is NOT fatal — the agent
    // recovers and keeps going. Render these as secondary, not as failures.
    { "name": "read_node", "input": { "short_id": "XYZ" }, "error": "No node with short_id or name \"XYZ\"" }
  ],

  // Only populated when the agent modified something. This is your cache
  // invalidation signal — refetch these nodes, or refresh the whole list.
  "nodes_touched": [
    { "short_id": "ABC123", "name": "Reading List", "action": "appended" }
  ],

  "usage": { "input_tokens": 3573, "output_tokens": 465 }
}
```

`action` is one of `created`, `appended`, `updated`.

`answer` is **markdown** — it uses bold, bullets, and headings. Render it as such.

## Errors

| Status | Body | Meaning |
|---|---|---|
| 401 | `"Bad credentials"` | Missing, unknown, or expired token. Note the body is a bare JSON **string**, not an object — don't blindly read `.error`. |
| 422 | `{ "error": "query is required" }` | Empty or whitespace-only query. |
| 422 | `{ "error": "…", "tool_calls": [...] }` | The agent run failed. Causes: the model declined the request; the 12-iteration cap was hit; the server has no API key configured. `tool_calls` shows how far it got. |
| 429 | `{ "error": "Throttle limit reached. Retry later." }` | Rate limit, with a `Retry-After` header (seconds). |
| 502 | `{ "error": "Upstream model error" }` | The model API itself failed. Retryable. |

## The one big UX constraint: this is slow and does not stream

The request is **synchronous** and holds the connection until the whole tool loop
finishes. Each iteration is a full model round trip with extended thinking, and the
loop runs up to **12 iterations**. Observed runs used 3–5 tool calls.

Wall-clock time was not formally measured, but treat this as a request that can run
for tens of seconds, not one that feels instant. Design accordingly:

- Set a generous client timeout. A default 10–30s `fetch` timeout may cut off valid
  requests.
- Never block the whole UI on it. The user should be able to keep reading and
  navigating while an answer is in flight.
- Show indeterminate progress. There is no streaming, no token-by-token output, and
  no progress events — U cannot show partial text or a real percentage. Don't build
  UI that implies U can.
- Guard against double-submit. There is no idempotency key, and a resubmitted
  write-intent query will apply the edit twice.

If a responsive, streaming feel becomes a requirement, that needs a server change
(SSE), not a client workaround. Flag it rather than faking it.

## Write behavior

The agent edits nodes when the query asks it to ("add X to my reading list",
"update my Y note"). Things to know:

- **Writes require a `full_access` token.** With a `read_only` token the write tools
  are not even offered to the model, and are refused server-side if it asks anyway.
  A read-only user asking to edit gets a normal answer explaining it couldn't.
- **Edits are applied immediately.** There is no dry-run, no preview, no
  confirmation step, and no undo. If U want the user to confirm before an edit
  lands, that is a server-side feature that does not exist yet — don't fake it
  client-side by asking first and sending after, since the model decides whether to
  write, not the client.
- **Every write bumps the node's `version`.** If your UI holds a node open in an
  editor while an agent query modifies it, your cached copy is stale. Use
  `nodes_touched` to detect this and reconcile before the user saves over it.

## Related endpoints for the rest of the UI

All use the same `Authorization` header.

| Endpoint | Returns |
|---|---|
| `GET /nodes` | All nodes (short form). With `?q=<search>`, full-text matches. |
| `GET /nodes/search?q=` | Single best match (full form). |
| `GET /nodes/:short_id` | One node (full form). |
| `POST /nodes` | Create. Body: `{ content }` or `{ name }`. |
| `PATCH /nodes/:short_id` | Update. Requires `version` **greater than** the server's, else 422 with `{ server_version, client_version }`. |
| `POST /nodes/:short_id/append` | Append `{ text }` to a node. |
| `DELETE /nodes/:short_id` | Delete. |
| `GET /tokens` | List the user's tokens. |
| `POST /tokens/read_only` | Mint a read-only token. |

Node shapes:

```jsonc
// full (NodeSerializer)
{ "id": "ABC123", "name": "Reading List", "content": "# Reading List\n\n- Dune", "version": 3, "is_private": false }

// short (NodeShortSerializer) — no content
{ "id": "ABC123", "name": "Reading List", "version": 3 }
```

## Gotchas that will bite U

1. **`id` in node JSON is the `short_id`, not a database id.** The serializer
   renames it. Every path parameter (`/nodes/:id`) expects a `short_id` too.

2. **`short_id`s contain arbitrary Unicode.** Real examples from production: `ǃ`,
   `iǰ`, `bỪ`, `lǱ`. They are not `[A-Za-z0-9]`. **Always URL-encode them** in paths
   and query strings, never assume ASCII, and never build one yourself. This is also
   why the agent's tools accept an exact node *name* wherever they accept a
   `short_id`.

3. **Optimistic locking is inverted from the usual convention.** `PATCH /nodes/:id`
   requires the `version` U send to be **strictly greater** than the stored one — U
   increment it client-side. Sending an equal version is rejected.

4. **CORS is an explicit allow-list**, in `config/initializers/cors.rb`. Currently:
   `zwiki.zencephalon.com`, `zwiki-client-react.vercel.app`, `localhost:3000`. A new
   frontend origin (including a Vercel preview URL) **will be blocked** until it is
   added there and the server redeployed.

5. **Rate limit: 20 requests per 5 seconds per IP**, across all endpoints. Fine for
   normal use; easy to trip with an aggressive polling loop or a burst of parallel
   node fetches. Honor `Retry-After` on 429.

6. **Content is markdown with two custom inline forms** — `[Text](short_id)` links
   and `{Text}(short_id)` embeds. A stock markdown renderer will render a link to a
   nonsense relative URL and will show the embed as literal text. Handle both if U
   render node content.

7. **`₴` is a privacy fold marker.** Content after it is stripped from public
   exports. It has no effect on the authenticated API — U get the full content — but
   don't render it as a literal currency symbol.
