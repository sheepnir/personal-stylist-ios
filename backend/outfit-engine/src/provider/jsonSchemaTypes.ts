/** Minimal JSON Schema typing for prompt output schemas (Draft 7 subset). */
export interface JSONSchema7 {
  type?: string | string[];
  enum?: readonly string[];
  const?: unknown;
  properties?: Record<string, JSONSchema7>;
  items?: JSONSchema7;
  required?: readonly string[];
  additionalProperties?: boolean | JSONSchema7;
  maxLength?: number;
  maxItems?: number;
  minimum?: number;
  description?: string;
}
