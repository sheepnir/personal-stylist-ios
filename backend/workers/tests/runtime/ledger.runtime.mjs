import assert from 'node:assert/strict';
import { after, before, test } from 'node:test';
import { mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { build } from 'esbuild';
import { Miniflare } from 'miniflare';

const DAY = '2030-06-15';
// Synthetic test caps only, unrelated to operational budgets.
const CAP = { dailyCapUSD: 1, softThresholdUSD: 0.5 };
let runtime;
let directory;
let script;
async function start() {
  runtime = new Miniflare({
    cf: false,
    resourcePersistencePath: join(directory, 'storage'),
    workers: [{ config: {
      type: 'worker', name: 'ledger-runtime-test', compatibilityDate: '2026-09-01', compatibilityFlags: ['nodejs_compat'],
      manifest: { mainModule: 'worker.mjs', modules: { 'worker.mjs': { type: 'esm', contents: script } } },
      env: { LEDGER: { type: 'durable-object', worker: 'ledger-runtime-test', exportName: 'RuntimeLedger' } },
      exports: { RuntimeLedger: { type: 'durable-object', storage: 'sqlite' } },
    } }],
  });
  await runtime.ready;
}
async function rpc(object, method, ...args) {
  const response = await runtime.dispatchFetch('https://example.invalid/rpc', {
    method: 'POST', body: JSON.stringify({ object, method, args }),
  });
  assert.equal(response.status, 200, await response.clone().text());
  return response.json();
}
async function clock(iso = `${DAY}T12:00:00.000Z`) { await rpc('clock', 'setClock', iso); }
async function summary(object, day = DAY) { return rpc(object, 'summary', day, CAP); }
before(async () => {
  directory = await mkdtemp(join(tmpdir(), 'ps-ledger-runtime-'));
  const bundled = await build({ entryPoints: ['tests/runtime/ledger-worker.ts'], bundle: true,
    format: 'esm', platform: 'neutral', external: ['cloudflare:workers', 'node:*'], write: false });
  script = bundled.outputFiles[0].text;
  await start();
});
after(async () => {
  await runtime?.dispose();
  if (directory) await rm(directory, { recursive: true, force: true });
});

test('concurrent RPC reservations cannot oversubscribe a cap', async () => {
  await clock();
  const results = await Promise.all(Array.from({ length: 40 }, (_, i) =>
    rpc('concurrency', 'reserve', `attempt_${i}`, 0.1, DAY, CAP, 'generate')));
  assert.equal(results.filter(result => result.ok).length, 10);
  assert.ok(results.filter(result => !result.ok).every(result => result.reason === 'hard_cap'));
  const state = await summary('concurrency');
  assert.equal(state.reservedUSD, 1);
  assert.equal(state.spentUSD, 0);
  assert.equal(state.hardCapReached, true);
});

test('duplicate reserves and reconciles across RPC are idempotent', async () => {
  await clock();
  const reserves = await Promise.all(Array.from({ length: 12 }, () =>
    rpc('duplicates', 'reserve', 'same_attempt', 0.2, DAY, CAP, 'generate')));
  assert.ok(reserves.every(result => result.ok));
  assert.equal((await summary('duplicates')).reservedUSD, 0.2);
  assert.equal((await rpc('duplicates', 'reserve', 'same_attempt', 0.3, DAY, CAP, 'generate')).ok, false);
  const reconciles = await Promise.all(Array.from({ length: 12 }, () =>
    rpc('duplicates', 'reconcile', DAY, 'same_attempt', 0.05, 'generate')));
  assert.ok(reconciles.every(result => result.ok));
  const state = await summary('duplicates');
  assert.equal(state.spentUSD, 0.05);
  assert.equal(state.reservedUSD, 0);
  assert.deepEqual(state.byTask, { generate: 0.05 });
  assert.equal((await rpc('duplicates', 'reserve', 'same_attempt', 0.2, DAY, CAP, 'generate')).reason, 'already_settled');
});

test('conflicting reconcile race settles exactly one amount', async () => {
  await clock();
  assert.equal((await rpc('reconcile_race', 'reserve', 'race', 0.4, DAY, CAP, 'generate')).ok, true);
  const results = await Promise.all([0.1, 0.2].map(amount =>
    rpc('reconcile_race', 'reconcile', DAY, 'race', amount, 'generate')));
  assert.equal(results.filter(result => result.ok).length, 1);
  assert.equal(results.filter(result => !result.ok)[0].reason, 'invalid');
  const state = await summary('reconcile_race');
  assert.equal(state.spentUSD, results[0].ok ? 0.1 : 0.2);
  assert.equal(state.reservedUSD, 0);
});

test('SQLite retains spent and held funds after a complete runtime restart', async () => {
  await clock();
  await rpc('restart', 'reserve', 'settled', 0.2, DAY, CAP, 'generate');
  await rpc('restart', 'reconcile', DAY, 'settled', 0.1, 'generate');
  await rpc('restart', 'reserve', 'held', 0.3, DAY, CAP, 'generate');
  const before = await summary('restart');
  await runtime.dispose();
  await start();
  await clock();
  assert.deepEqual(await summary('restart'), before);
  assert.equal(before.spentUSD, 0.1);
  assert.equal(before.reservedUSD, 0.3);
});

test('unknown generation metadata and held funds survive restart', async () => {
  await clock();
  await rpc('unknown', 'reserve', 'unknown_attempt', 0.8, DAY, CAP, 'generate');
  assert.equal((await rpc('unknown', 'markUnknown', DAY, 'unknown_attempt', 'synthetic_generation')).ok, true);
  const storedBefore = await rpc('unknown', 'inspect', DAY);
  assert.ok(JSON.stringify(storedBefore).includes('synthetic_generation'));
  await runtime.dispose();
  await start();
  await clock();
  assert.deepEqual(await rpc('unknown', 'inspect', DAY), storedBefore);
  assert.equal((await summary('unknown')).reservedUSD, 0.8);
  assert.equal((await rpc('unknown', 'reserve', 'extra', 0.3, DAY, CAP, 'generate')).reason, 'hard_cap');
  assert.equal((await rpc('unknown', 'reconcile', DAY, 'unknown_attempt', 0.15, 'generate')).ok, true);
  assert.equal((await summary('unknown')).spentUSD, 0.15);
});

test('UTC midnight separates caps and refuses replay of a stale hold', async () => {
  await clock(`${DAY}T23:59:59.999Z`);
  assert.equal((await rpc('midnight', 'reserve', 'old', 1, DAY, CAP, 'generate')).ok, true);
  await clock('2030-06-16T00:00:00.000Z');
  assert.equal((await rpc('midnight', 'reserve', 'old', 1, DAY, CAP, 'generate')).reason, 'stale_hold');
  assert.equal((await rpc('midnight', 'reserve', 'new', 1, '2030-06-16', CAP, 'generate')).ok, true);
  assert.equal((await summary('midnight', DAY)).reservedUSD, 1);
  assert.equal((await summary('midnight', '2030-06-16')).reservedUSD, 1);
  assert.equal((await rpc('midnight', 'reconcile', DAY, 'old', 0.1, 'generate')).ok, true);
  assert.equal((await summary('midnight', '2030-06-16')).reservedUSD, 1);
  assert.equal((await rpc('midnight', 'reserve', 'far_future', 0.1, '2030-06-18', CAP, 'generate')).reason, 'invalid');
  assert.equal((await rpc('midnight', 'reserve', 'far_past', 0.1, '2030-05-15', CAP, 'generate')).reason, 'invalid');
});

test('unknown funds age at 24 hours and settlement metadata persists across restart', async () => {
  await clock();
  await rpc('aging', 'reserve', 'aging_attempt', 0.6, DAY, CAP, 'generate');
  await rpc('aging', 'markUnknown', DAY, 'aging_attempt', 'synthetic_aging_generation');
  await clock('2030-06-16T11:59:59.999Z');
  assert.equal((await summary('aging')).reservedUSD, 0.6);
  await clock('2030-06-16T12:00:00.000Z');
  const aged = await summary('aging');
  assert.equal(aged.reservedUSD, 0);
  assert.equal(aged.spentUSD, 0.6);
  const stored = await rpc('aging', 'inspect', DAY);
  assert.equal(stored.a.aging_attempt.S, 1);
  assert.equal(stored.a.aging_attempt.a, 600000);
  await runtime.dispose();
  await start();
  await clock('2030-06-16T12:00:00.000Z');
  assert.deepEqual(await rpc('aging', 'inspect', DAY), stored);
  assert.deepEqual(await summary('aging'), aged);
  assert.equal((await rpc('aging', 'markUnknown', DAY, 'aging_attempt', 'synthetic_aging_generation')).ok, true);
  assert.equal((await rpc('aging', 'markUnknown', DAY, 'aging_attempt', 'different_generation')).ok, false);
  assert.equal((await rpc('aging', 'reconcile', DAY, 'aging_attempt', 0.1, 'generate')).ok, false);
  assert.equal((await summary('aging')).spentUSD, 0.6);
});

test('unknown outcomes cannot release funds and retention honors the 30-day boundary', async () => {
  await clock();
  await rpc('retention', 'reserve', 'retained_attempt', 0.9, DAY, CAP, 'generate');
  await rpc('retention', 'markUnknown', DAY, 'retained_attempt');
  assert.equal((await rpc('retention', 'reserve', 'retained_attempt', 0.9, DAY, CAP, 'generate')).reason, 'already_settled');
  assert.equal((await summary('retention')).reservedUSD, 0.9);
  await clock('2030-07-15T12:00:00.000Z');
  assert.equal((await summary('retention')).spentUSD, 0.9);
  assert.ok(await rpc('retention', 'inspect', DAY));
  await clock('2030-07-16T12:00:00.000Z');
  await summary('retention', '2030-07-16');
  assert.equal(await rpc('retention', 'inspect', DAY), null);
});

test('global switch defaults off, survives restart, and stops new reservations', async () => {
  await clock();
  const object = 'global_switch';
  assert.equal(await rpc(object, 'providerEnabled'), false);
  assert.equal((await rpc(object, 'reserveGlobal', 'disabled', 0.1, DAY, CAP, 2, 'generate')).ok, false);
  await rpc(object, 'setProviderEnabled', true);
  assert.equal(await rpc(object, 'providerEnabled'), true);
  await runtime.dispose();
  await start();
  await clock();
  assert.equal(await rpc(object, 'providerEnabled'), true);
  assert.equal((await rpc(object, 'reserveGlobal', 'enabled', 0.1, DAY, CAP, 2, 'generate')).ok, true);
  await rpc(object, 'setProviderEnabled', false);
  assert.equal((await rpc(object, 'reserveGlobal', 'stopped', 0.1, DAY, CAP, 2, 'generate')).ok, false);
  assert.equal((await summary(object)).reservedUSD, 0.1);
  assert.equal((await rpc(object, 'reconcile', DAY, 'enabled', 0.02, 'generate')).ok, true);
});

test('global daily cap serializes concurrent attempts from multiple devices', async () => {
  await clock();
  const object = 'global_daily';
  await rpc(object, 'setProviderEnabled', true);
  const results = await Promise.all(Array.from({ length: 40 }, (_, i) =>
    rpc(object, 'reserveGlobal', `synthetic_device_${i}`, 0.1, DAY, CAP, 10, 'generate')));
  assert.equal(results.filter(result => result.ok).length, 10);
  assert.ok(results.filter(result => !result.ok).every(result => result.reason === 'hard_cap'));
  assert.equal((await summary(object)).reservedUSD, 1);
});

test('cumulative evaluation cap never refunds or resets across dates and restart', async () => {
  await clock();
  const object = 'global_total';
  await rpc(object, 'setProviderEnabled', true);
  assert.equal((await rpc(object, 'reserveGlobal', 'first_day', 0.75, DAY, CAP, 1.5, 'generate')).ok, true);
  assert.equal((await rpc(object, 'reconcile', DAY, 'first_day', 0, 'generate')).ok, true);
  await clock('2030-06-16T12:00:00.000Z');
  assert.equal((await rpc(object, 'reserveGlobal', 'second_day', 0.75, '2030-06-16', CAP, 1.5, 'generate')).ok, true);
  await runtime.dispose();
  await start();
  await clock('2030-06-17T12:00:00.000Z');
  assert.equal((await rpc(object, 'reserveGlobal', 'third_day', 0.01, '2030-06-17', CAP, 1.5, 'generate')).reason, 'hard_cap');
  assert.equal((await summary(object, '2030-06-17')).reservedUSD, 0);
});

test('duplicate global hold stays idempotent at the cumulative cap', async () => {
  await clock();
  const object = 'global_duplicate';
  await rpc(object, 'setProviderEnabled', true);
  assert.equal((await rpc(object, 'reserveGlobal', 'same', 1, DAY, CAP, 1, 'generate')).ok, true);
  assert.equal((await rpc(object, 'reserveGlobal', 'same', 1, DAY, CAP, 1, 'generate')).ok, true);
  assert.equal((await summary(object)).reservedUSD, 1);
});

test('alarm backoff survives restart and synthetic known cost settles an unknown outcome', async () => {
  await clock();
  const object = 'alarm_backoff';
  await rpc(object, 'reserve', 'alarm_attempt', 0.4, DAY, CAP, 'generate');
  await rpc(object, 'markUnknown', DAY, 'alarm_attempt', 'synthetic_alarm_generation');
  await clock(`${DAY}T12:01:00.000Z`);
  assert.equal(await rpc(object, 'runAlarmForTest', null), 1);
  const stored = await rpc(object, 'inspect', DAY);
  assert.equal(stored.a.alarm_attempt.n, 1);
  assert.equal((await summary(object)).reservedUSD, 0.4);
  await runtime.dispose();
  await start();
  await clock(`${DAY}T12:01:00.000Z`);
  assert.deepEqual(await rpc(object, 'inspect', DAY), stored);
  assert.equal(await rpc(object, 'runAlarmForTest', 0.08), 0);
  await clock(`${DAY}T13:00:00.000Z`);
  assert.equal(await rpc(object, 'runAlarmForTest', 0.08), 1);
  const settled = await summary(object);
  assert.equal(settled.spentUSD, 0.08);
  assert.equal(settled.reservedUSD, 0);
});

test('one alarm limits lookups to 20 and leaves skipped unknown backoff untouched', async () => {
  await clock();
  const object = 'alarm_batch';
  const ids = Array.from({ length: 27 }, (_, i) => `batch_${i}`);
  for (const id of ids) {
    assert.equal((await rpc(object, 'reserve', id, 0.01, DAY, CAP, 'generate')).ok, true);
    assert.equal((await rpc(object, 'markUnknown', DAY, id, `synthetic_${id}`)).ok, true);
  }
  await clock(`${DAY}T12:01:00.000Z`);
  assert.equal(await rpc(object, 'runAlarmForTest', null), 20);
  const first = (await rpc(object, 'inspect', DAY)).a;
  const tried = ids.filter(id => first[id].n === 1);
  const skipped = ids.filter(id => first[id].n === undefined);
  assert.equal(tried.length, 20);
  assert.equal(skipped.length, 7);
  for (const id of skipped) {
    assert.equal(first[id].l, undefined);
    assert.equal(first[id].S, 2);
  }
  // Same clock: the attempted records are in backoff, while skipped records remain due.
  assert.equal(await rpc(object, 'runAlarmForTest', 0.002), 7);
  const second = (await rpc(object, 'inspect', DAY)).a;
  for (const id of tried) assert.deepEqual(second[id], first[id]);
  for (const id of skipped) {
    assert.equal(second[id].n, 1);
    assert.equal(second[id].S, 1);
    assert.equal(second[id].a, 2000);
  }
  const state = await summary(object);
  assert.equal(state.reservedUSD, 0.2);
  assert.equal(state.spentUSD, 0.014);
});
