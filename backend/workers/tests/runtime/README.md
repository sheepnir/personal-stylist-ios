# Ledger tests in workerd

Run `npm ci` then `npm run test:runtime` from `backend/workers` (Node 22+).
This is a separate Node test runner suite; `npm test` continues to run the Node/Vitest unit tests.
CI can run both commands as separate steps. The runner needs permission to open loopback listeners.

The harness bundles the production `DeviceSpendLedger` with esbuild and executes it in
Miniflare's real workerd runtime with SQLite-backed Durable Objects. Requests pass through a
Worker gateway and actual Durable Object RPC. Persistence tests dispose the runtime, create
a fresh runtime using the same temporary storage directory, and verify saved state.

The test-only subclass adds clock control, read-only inspection of persisted buckets, and
a wrapper that invokes the production alarm handler with synthetic cost responses.
It does not replace reserve, reconcile, markUnknown, summary, transactions, storage, or RPC.
The clock is shared inside the test Worker, so tests intentionally run sequentially; concurrent
reservation/reconciliation cases explicitly issue overlapping requests with `Promise.all`.
All clock values, attempt IDs, generation IDs and cap values are synthetic.
The global fetch implementation always throws or returns an in-memory synthetic cost response;
it never delegates to a network implementation.

Coverage includes concurrent cap enforcement, duplicate operations, conflicting reconciliation,
held/spent funds after restart, unknown outcome metadata, conservative settlement at exactly
24 hours, UTC midnight, stale hold replay, day bounds, 30-day retention, the global kill
switch, application-wide concurrent caps, nonresetting evaluation limits, and alarm backoff
metadata across restart followed by reconciliation to a synthetic known cost. A 27-attempt
batch proves one alarm performs at most 20 lookups and leaves skipped backoff counters
untouched so the next alarm can process the remainder.

No provider calls, production credentials, deployed resources, fault-injected disk failures,
or distributed Cloudflare deployment behavior are exercised. Temporary SQLite files are removed
when the suite exits. The test gateway and clock override are never part of the production entry point.

Miniflare and esbuild are direct development dependencies pinned to the versions already in
the Wrangler dependency tree. Miniflare v5 uses its native `workers` configuration and
`resourcePersistencePath`; its legacy v4 converter does not preserve `durableObjectsPersist`.
