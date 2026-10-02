import { it, expect } from 'vitest';
import { promptHash, JEV_PROMPT_VERSION } from '../src/jev.js';
it('keeps outfit-choice-v1 immutable', () => {
  expect(JEV_PROMPT_VERSION).toBe('outfit-choice-v1');
  expect(promptHash).toBe('4acad8fec13f86a7c383894bdf85a0b74942f93963d9743655e0573c7976e300');
});
