# Transcript Cleanup Benchmarks

This directory stores local transcript-cleanup benchmark assets.

The benchmark contract is intentionally product-focused:

- deterministic cleanup must pass exact, case-sensitive expectations;
- model-forced hard cases must prove a candidate model is better before it can become default;
- `contains_any` may be used for equivalent punctuation or typography variants;
- hybrid product runs must report route, latency, fallback, memory, and severe-error counts;
- audio end-to-end manifests should be added before claiming everyday-user consistency.

Normal users should not choose cleanup models. A new bundled cleanup model can become the default only after it beats the current baseline on quality, latency, memory, and protected-span safety.

## Current Seed Assets

- `suites/hybrid_product.jsonl`: seeded from the local Gemma 3n E4B hybrid evaluation harness.
- `results/gemma3n_e4b_hybrid_summary.json`: one-pass baseline summary.
- `results/gemma3n_e4b_hybrid_stability_summary.json`: two-pass stability summary.

## Required Future Suites

- `deterministic_unit`
- `model_forced`
- `validator_adversarial`
- `timeout_unavailable`
- `terminal_lockdown`
- `developer_text`
- `privacy`
- `resource`
- `audio_e2e`
