import { it, expect } from 'vitest';
import { createHash } from 'node:crypto';
import { lunaRequestBody, LUNA_PROMPT_VERSION } from '../src/luna.js';
it('freezes Luna instructions, schema, routing and bounded settings under a prompt version',()=>{
  const body=lunaRequestBody([{token:'a',result:null,garments:[]},{token:'b',result:null,garments:[]}],
    {occasion:'WORK_STANDARD',occasionFormality:3,temperatureBand:'MILD'},
    {prompt:0.0000002,completion:0.0000012,context:28096,maxOutput:1024});
  expect(LUNA_PROMPT_VERSION).toBe('outfit-choice-luna-v1');
  expect(createHash('sha256').update(body).digest('hex')).toBe('dbbdecedbbdb1ee0aeb31d7c629870525f39ff85f2a52ec606696f09b2d377ef');
});
