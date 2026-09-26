import { describe, it, expect } from 'vitest';
import { assertRpcPlainDeep } from '../src/rpcPlain.js';

describe('assertRpcPlainDeep', () => {
  it('rejects bigint, symbol, and function values', () => {
    expect(() => assertRpcPlainDeep(1n)).toThrow(/bigint/);
    expect(() => assertRpcPlainDeep(Symbol('x'))).toThrow(/symbol/);
    expect(() => assertRpcPlainDeep(() => {})).toThrow(/function/);
    expect(() => assertRpcPlainDeep({ fn: () => {} })).toThrow(/function/);
  });
});
