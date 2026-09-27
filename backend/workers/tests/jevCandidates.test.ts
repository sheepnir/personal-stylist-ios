import { describe, it, expect } from 'vitest';
import { generateLocal, isLocalProblem, rankAlternatives, isAlternativesProblem } from '@personal-stylist/outfit-engine';
import { resolveScenarioIds, loadScenarioById, requestFromScenario, alternativesBaseFromScenario } from '../../outfit-engine/src/eval/scenarios.js';
import { generateCandidates, swapCandidates, validateDecision, JEV_MODEL, requestBody } from '../src/jev.js';
import { fileURLToPath } from 'node:url';
const root = fileURLToPath(new URL('../../../fixtures/', import.meta.url));
const ids = resolveScenarioIds(root, 'all');
const price = {prompt:0.000000042,completion:0,context:32000,maxOutput:28800};

describe('synthetic candidate evaluation against deterministic engine',()=>{
  for(const id of ids) {
    it(id,()=>{
      const scenario=loadScenarioById(root,id);
      if(scenario.steps) {
        const base=alternativesBaseFromScenario(scenario,root);
        for(const step of scenario.steps) {
          const input={...base,...step.request};
          const baseline=rankAlternatives(input);
          if(isAlternativesProblem(baseline)) continue;
          const choices=swapCandidates(input,baseline);
          for(const c of choices) {
            expect(c.result.alternatives).toHaveLength(baseline.alternatives.length);
            expect(new Set(c.result.alternatives.map(a=>a.garmentId))).toEqual(new Set(baseline.alternatives.map(a=>a.garmentId)));
            expect(c.result.alternatives[0].setPartnerIds).toEqual(baseline.alternatives.find(a=>a.garmentId===c.result.alternatives[0].garmentId)?.setPartnerIds);
          }
        }
        return;
      }
      const input=requestFromScenario(scenario,root);
      const baseline=generateLocal(input);
      if(isLocalProblem(baseline)) return;
      const choices=generateCandidates(input,baseline);
      if (baseline.assignments.some(a => !a.garmentId && a.gapReason)) {
        expect(choices.every(c => !c.result.assignments.some(a => !a.garmentId && a.gapReason))).toBe(true);
        return;
      }
      expect(choices.length).toBeGreaterThan(0);
      const exclude=[...(input.options?.excludeGarmentSets ?? [])];
      for(const c of choices) {
        const verified=generateLocal({...input,options:{...input.options,excludeGarmentSets:exclude}});
        expect(isLocalProblem(verified)).toBe(false);
        if(isLocalProblem(verified)) throw new Error('candidate verification failed');
        expect(c.result.assignments).toEqual(verified.assignments);
        const members=c.result.assignments.flatMap(a=>a.garmentId?[a.garmentId]:[]);
        expect(members.every(member=>input.wardrobe.some(g=>g.id===member))).toBe(true);
        if(input.anchorGarmentId) expect(members).toContain(input.anchorGarmentId);
        for(const lock of input.lockedAssignments ?? []) if(lock.garmentId) expect(members).toContain(lock.garmentId);
        exclude.push(members);
        const response={model:JEV_MODEL,answers:{outfit:{type:'choice',choice:c.token,confidence:1,probabilities:Object.fromEntries(choices.map(x=>[x.token,x===c?1:0]))}},usage:{input_tokens:100,output_tokens:10}};
        expect(validateDecision(response,choices).result).toBe(c.result);
      }
      const payload=requestBody(choices,input.context,price);
      for(const g of input.wardrobe) expect(payload).not.toContain(g.id);
      expect(payload).not.toContain('displayName');
      expect(payload).not.toContain('image');
    });
  }
});

it('never offers an outfit missing required footwear to Jev', () => {
  const scenario = ids.map(id => loadScenarioById(root, id)).find(s => !s.steps)!;
  const original = requestFromScenario(scenario, root);
  const input = { ...original, anchorGarmentId: undefined, lockedAssignments: [], wardrobe: original.wardrobe.filter(g => g.slot !== 'FOOTWEAR') };
  const result = generateLocal(input);
  expect(isLocalProblem(result)).toBe(false);
  if (isLocalProblem(result)) throw new Error('fixture did not produce a gapped outfit');
  expect(result.assignments.some(a => a.slot === 'FOOTWEAR' && !a.garmentId)).toBe(true);
  expect(generateCandidates(input, result)).toEqual([]);
});
