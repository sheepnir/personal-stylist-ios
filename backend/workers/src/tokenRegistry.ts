import { DurableObject } from 'cloudflare:workers';
import type { Env } from './types.js';
import type { TokenRecord } from './tokens.js';

type StoredToken = TokenRecord & { tokenHash: string };

/** One coordination object per random device ID; stores hashes, never raw tokens. */
export class DeviceTokenRegistry extends DurableObject<Env> {
  lookup(tokenHash: string): TokenRecord | null {
    const stored = this.ctx.storage.kv.get<StoredToken>('token');
    if (!stored || stored.tokenHash !== tokenHash) return null;
    return { status: stored.status, issuedAt: stored.issuedAt, revokedAt: stored.revokedAt };
  }

  issue(tokenHash: string, issuedAt: string): boolean {
    return this.ctx.storage.transactionSync(() => {
      if (this.ctx.storage.kv.get('token')) return false;
      this.ctx.storage.kv.put('token', { tokenHash, issuedAt, status: 'active' });
      return true;
    });
  }

  revoke(tokenHash: string): boolean {
    return this.ctx.storage.transactionSync(() => {
      const stored = this.ctx.storage.kv.get<StoredToken>('token');
      if (!stored || stored.tokenHash !== tokenHash || stored.status !== 'active') return false;
      this.ctx.storage.kv.put('token', { ...stored, status: 'revoked', revokedAt: new Date().toISOString() });
      return true;
    });
  }

  rotate(oldHash: string, newHash: string, issuedAt: string): boolean {
    return this.ctx.storage.transactionSync(() => {
      const stored = this.ctx.storage.kv.get<StoredToken>('token');
      if (!stored || stored.tokenHash !== oldHash || stored.status !== 'active') return false;
      this.ctx.storage.kv.put('token', { tokenHash: newHash, issuedAt, status: 'active' });
      return true;
    });
  }
}
