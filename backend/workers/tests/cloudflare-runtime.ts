// Node unit tests mock Durable Object base state; ledger behavior uses fake storage in tests, not workerd.
export class DurableObject<Env = unknown> {
  protected ctx: DurableObjectState;
  protected env: Env;
  constructor(ctx: DurableObjectState, env: Env) {
    this.ctx = ctx;
    this.env = env;
  }
}
