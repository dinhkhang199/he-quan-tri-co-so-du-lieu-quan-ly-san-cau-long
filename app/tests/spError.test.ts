import assert from 'node:assert/strict';
import test from 'node:test';
import { mapSqlError } from '../src/shared/spError.js';

test('maps deadlock without exposing technical detail as the user message', () => {
  const mapped = mapSqlError(Object.assign(new Error('driver internals'), { number: 1205 }));
  assert.equal(mapped.code, 1205);
  assert.match(mapped.message ?? '', /1205/);
  assert.doesNotMatch(mapped.message ?? '', /driver internals/);
});

test('unknown and non-object errors remain unmapped', () => {
  assert.equal(mapSqlError(new Error('socket failed')).message, null);
  assert.equal(mapSqlError(null).code, null);
});
