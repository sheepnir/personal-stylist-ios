/** Test-only entry point: never bundled by the deployed Worker. */
import { DeviceSpendLedger } from '../../src/spendLedger.js';

const RealDate = Date;
let testNow = RealDate.parse('2030-06-15T12:00:00.000Z');
// Only the clock is controlled. RPC, transactions, KV and SQLite use real workerd.
class TestDate extends RealDate {
  constructor(value?: string | number) { super(value === undefined ? testNow : value); }
  static now() { return testNow; }
}
globalThis.Date = TestDate as DateConstructor;
// Fail closed even if future ledger code accidentally attempts external I/O.
let mockCost: number | null = null;
let fetchCount = 0;
globalThis.fetch = async () => {
  fetchCount++;
  if (mockCost === null) throw new Error('RUNTIME_TEST_NETWORK_DISABLED');
  return Response.json({ data: { total_cost: mockCost } });
};

export class RuntimeLedger extends DeviceSpendLedger {
  setClock(iso: string) { testNow = RealDate.parse(iso); }
  async runAlarmForTest(cost: number | null) {
    this.env.OPENROUTER_API_KEY = 'synthetic-test-key';
    mockCost = cost;
    fetchCount = 0;
    try { await this.alarm(); return fetchCount; }
    finally { mockCost = null; this.env.OPENROUTER_API_KEY = undefined; }
  }
  inspect(day: string) { return this.ctx.storage.kv.get(`bucket:${day}`) ?? null; }
}

export default {
  async fetch(request: Request, env: { LEDGER: DurableObjectNamespace<RuntimeLedger> }) {
    const { object, method, args } = await request.json() as {
      object: string; method: string; args: unknown[];
    };
    const stub = env.LEDGER.getByName(object);
    // Test-only gateway; each request crosses a real Worker -> Durable Object RPC boundary.
    const result = await (stub as unknown as Record<string, (...values: unknown[]) => Promise<unknown>>)[method](...args);
    return Response.json(result ?? null);
  },
};
