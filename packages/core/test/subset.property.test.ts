import { describe, expect, it } from 'vitest';
import {
  assertActionIsSubset,
  assertLeaseIsSubset,
  fixtureAction,
  fixtureLease,
  fixturePolicy,
  testAccounts,
  FIXTURE,
  type AgentLease,
} from '../src/index.js';

// Deterministic property tests (seeded, no network). Each iteration draws random values; the
// invariant is "anything within the root's caps passes, and widening any single cap by one unit fails".
let state = 0x2545f491n;
const next = (): bigint => {
  // xorshift64* on BigInt, reproducible across runs and hosts
  state ^= state >> 12n; state &= (1n << 64n) - 1n;
  state ^= state << 25n; state &= (1n << 64n) - 1n;
  state ^= state >> 27n;
  return (state * 0x2545f4914f6cdd1dn) & ((1n << 64n) - 1n);
};
const upTo = (max: bigint): bigint => (max === 0n ? 0n : next() % (max + 1n));

const ctx = {
  now: 1_800_000_100n,
  controllers: [testAccounts.controllerA.address, testAccounts.controllerB.address],
  chainRef: FIXTURE.suiChainRef,
  account: FIXTURE.suiAccount,
};
const policy = fixturePolicy();
const rootAsset = policy.endpoints[1]!.assets[0]!;
const withUsd = (lease: AgentLease, cap: { maxPerAction: bigint; maxPerEpoch: bigint; maxTotal: bigint }): AgentLease => ({
  ...lease,
  endpoints: lease.endpoints.map((e) =>
    e.chainRef === ctx.chainRef ? { ...e, assets: e.assets.map((a) => (a.assetId === FIXTURE.usd ? { ...a, ...cap } : a)) } : e,
  ),
});

describe('lease caps are a strict subset of the root (property)', () => {
  it('any caps not above the root caps are accepted', () => {
    for (let i = 0; i < 300; i++) {
      const cap = { maxPerAction: upTo(rootAsset.maxPerAction), maxPerEpoch: upTo(rootAsset.maxPerEpoch), maxTotal: upTo(rootAsset.maxTotal) };
      expect(() => assertLeaseIsSubset(policy, withUsd(fixtureLease(), cap), ctx)).not.toThrow();
    }
  });
  it('widening any single cap by one unit is rejected', () => {
    for (let i = 0; i < 300; i++) {
      const cap = { maxPerAction: rootAsset.maxPerAction, maxPerEpoch: rootAsset.maxPerEpoch, maxTotal: rootAsset.maxTotal };
      const field = (['maxPerAction', 'maxPerEpoch', 'maxTotal'] as const)[Number(next() % 3n)]!;
      cap[field] += 1n + upTo(1_000_000n);
      expect(() => assertLeaseIsSubset(policy, withUsd(fixtureLease(), cap), ctx)).toThrow('AMANE_LEASE_CAP_EXCEEDS_ROOT');
    }
  });
  it('lifetime above the root maximum is rejected, at or below is accepted', () => {
    for (let i = 0; i < 200; i++) {
      const base = fixtureLease();
      const ok = 1n + upTo(policy.maxLeaseLifetime - 1n);
      expect(() => assertLeaseIsSubset(policy, { ...base, expiresAt: base.validAfter + ok }, ctx)).not.toThrow();
      const bad = policy.maxLeaseLifetime + 1n + upTo(10_000n);
      expect(() => assertLeaseIsSubset(policy, { ...base, expiresAt: base.validAfter + bad }, ctx)).toThrow('AMANE_LEASE_LIFETIME_EXCEEDED');
    }
  });
  it('an action mask bit outside the root mask is rejected', () => {
    const rootMask = policy.allowedActions;
    for (let bit = 0; bit < 32; bit++) {
      const m = 1 << bit;
      if ((rootMask & m) !== 0) continue;
      expect(() => assertLeaseIsSubset(policy, { ...fixtureLease(), allowedActions: (rootMask | m) >>> 0 }, ctx)).toThrow('AMANE_LEASE_ACTION_NOT_IN_ROOT');
    }
  });
});

describe('action amounts and recipients (property)', () => {
  const lease = fixtureLease();
  const perAction = lease.endpoints[1]!.assets[0]!.maxPerAction;
  it('every amount in 1..perAction passes the stateless check, any amount above fails', () => {
    for (let i = 0; i < 300; i++) {
      const amount = 1n + upTo(perAction - 1n);
      expect(() => assertActionIsSubset(policy, lease, fixtureAction({ amountIn: amount }), ctx)).not.toThrow();
      const over = perAction + 1n + upTo(10n ** 18n);
      expect(() => assertActionIsSubset(policy, lease, fixtureAction({ amountIn: over }), ctx)).toThrow('AMANE_BUDGET_PER_ACTION');
    }
  });
  it('a PAY to any recipient other than the pinned one is rejected', () => {
    for (let i = 0; i < 200; i++) {
      const other = `0x${(next() | 1n).toString(16).padStart(64, '0')}` as `0x${string}`;
      if (other === FIXTURE.merchant) continue;
      expect(() => assertActionIsSubset(policy, lease, fixtureAction({ recipient: other }), ctx)).toThrow('AMANE_ACTION_RECIPIENT_NOT_ALLOWED');
    }
  });
  it('time outside the lease window or after the deadline is rejected', () => {
    for (let i = 0; i < 200; i++) {
      const before = lease.validAfter - 1n - upTo(100_000n);
      const after = lease.expiresAt + 1n + upTo(100_000n);
      expect(() => assertActionIsSubset(policy, lease, fixtureAction(), { ...ctx, now: before })).toThrow('AMANE_LEASE_NOT_YET_VALID');
      expect(() => assertActionIsSubset(policy, lease, fixtureAction(), { ...ctx, now: after })).toThrow('AMANE_LEASE_EXPIRED');
    }
  });
});
