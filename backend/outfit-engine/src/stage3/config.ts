import type { BuilderConfig, Slot } from "../types.js";

export const DEFAULT_FILL_ORDER: Slot[] = [
  "TOP",
  "BOTTOM",
  "FOOTWEAR",
  "MID_LAYER",
  "JACKET",
  "OUTERWEAR",
  "ACCESSORY",
];

export const DEFAULT_BUILDER_CONFIG: BuilderConfig = {
  fillOrder: [...DEFAULT_FILL_ORDER],
  fillOptionalAccessories: false,
  maxAccessories: 3,
  builderModelId: "deterministic-v0",
  assignmentOrder: "FILL_ORDER_INLINE_GAPS",
};

export function resolveBuilderConfig(
  override?: Partial<BuilderConfig> | null,
): BuilderConfig {
  if (!override) {
    return {
      ...DEFAULT_BUILDER_CONFIG,
      fillOrder: [...DEFAULT_BUILDER_CONFIG.fillOrder],
    };
  }
  return {
    ...DEFAULT_BUILDER_CONFIG,
    ...override,
    fillOrder: override.fillOrder
      ? [...override.fillOrder]
      : [...DEFAULT_BUILDER_CONFIG.fillOrder],
  };
}
