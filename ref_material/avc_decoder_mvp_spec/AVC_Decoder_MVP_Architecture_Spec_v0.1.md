# AVC Decoder MVP Architecture Spec v0.1

> Status: **Phase-1 directed RTL verification for T02 and T07 is closed** against RTL baseline `3a124096f71b3a6c9ccf04fab52b48f8db8f4ed7`, using Synopsys VCS W-2024.09-SP2-2. This record does not claim full-chip, bitstream-level, formal, coverage-closure, or production signoff.

## 0. Source of truth and scope

`ref_material/avc_decoder_mvp_spec/gen_spec.py` is the reproducible source of truth for this Markdown file, the canonical root diagram, and the three detailed figure pairs. It writes only beneath `ref_material/`.

The executable hierarchy is the authority:

```text
vc_mvp_dec_top
+- vc_mvp_dec_backend_top
   +- vc_mvp_dec_neib_top
   |  +- vc_mvp_dec_ctrl
   |  +- vc_mvp_dec_neib_adapter
   |  +- real vc_mvp_get_neib hierarchy
   |  `- vc_mvp_dec_upd_adapter
   +- vc_mvp_dec_recon
   +- vc_mvp_dec_mc_adapter
`- vc_mvp_dec_cand
   `- real vc_mvp_cand_gen
```

Phase 1 supports P16x16, P8x8, and P_SKIP; List0 with one active reference and legal `ref_idx=0`. List1, temporal and Col candidates, reference traversal, scaling, encoder search, and cost selection are inactive.

## 1. Canonical transaction flow

```text
accepted decoded syntax
  -> DEC_NEIB
  -> real Neighbor result
  -> Candidate capture
  -> reconstruction
  -> DEC_SEND
  -> decoder MC adapter
  -> reused mrg2mc interface
  -> MC acknowledgement
  -> mc_commit
  -> cur_cu_upd
  -> rolling Neighbor state
```

`vc_mvp_dec_ctrl` owns the Decoder transaction state. The final MV is emitted directly by the Decoder MC adapter through the reused `mrg2mc` branch. The acknowledgement is `mc2mrg_cand_ack`; retirement is `mc_commit`; `dec_mrg2mc_cand_done` is the registered one-cycle completion pulse toward MC; `cur_cu_upd` is generated from the same accepted handshake.

## 2. Candidate behavior

The real `vc_mvp_cand_gen` AVC MED path is wrapped by `vc_mvp_dec_cand`.

- A = A1 = `neib_a[1]`.
- B = B1 = `neib_b[1]`.
- C = B0 when available, otherwise B2.
- A0 is masked by `vc_mvp_dec_cand`.
- B0 has priority when B0 and B2 are both available.
- Candidate0 is consumed; Candidate1 is disabled.

| Available operands | Candidate-0 result |
|---|---|
| none | zero |
| A only | A1 |
| B only | B1 |
| C only | B0, otherwise B2 fallback |
| A+B | signed component-wise MED(A, B, 0) |
| A+C | signed component-wise MED(A, 0, C) |
| B+C | signed component-wise MED(0, B, C) |
| A+B+C | signed component-wise MED(A, B, C) |

Candidate data is combinational during the accepted start/IDLE cycle. `vc_mvp_dec_cand` captures candidate0 on the launch edge and reports `cand_capture_done` as the handoff event. Legacy Candidate-generator `cand_blk_done` is not the Decoder data-valid event.

Phase-1 inputs are deterministic: `NUM_REF=1`, Candidate-side `cur_ref_idx=0`, Neighbor reference fields sanitized to zero, temporal/Col and scaling paths disabled, and legal decoded reference index zero. The legacy reference-index field remains structurally present but is not used for Phase-1 traversal or remapping.

Evidence: `src_dec_dev/vc_mvp_dec_cand.v:31-116`, `src_encoder_ref/vc_mvp_cand_gen.v:203-215`, `src_encoder_ref/vc_mvp_cand_gen.v:411-445`, `src_encoder_ref/vc_mvp_cand_gen.v:1211-1224`, `src_encoder_ref/vc_mvp_cand_gen.v:1329-1330`.

## 3. Reconstruction and P_SKIP

For normal Inter, MVP X/Y and MVD X/Y are interpreted as signed 16-bit two's-complement components. Each operand is explicitly sign-extended to signed 17 bits, added independently, and retained as the low 16 bits:

```text
MVP X/Y + MVD X/Y
  -> signed 17-bit component-wise addition
  -> sum_x[15:0] and sum_y[15:0]
  -> final MV = {sum_y[15:0], sum_x[15:0]}
```

This is low-bit modulo retention, not saturation. Out-of-range sums produce simulation-only diagnostics; no recovery output is exposed.

The implemented P_SKIP condition is:

```text
skip_zero_motion =
    picture_top16
 || picture_left16
 || (B1 available && B1 MV == 0)
 || (A1 available && A1 MV == 0)
```

When true, final MV is zero. Otherwise final MV is the spatial MVP. P_SKIP final `ref_idx` is zero and MVD is ignored. Picture-boundary flags are derived from accepted and latched CTU/CU coordinates, not live upstream coordinates.

Evidence: `src_dec_dev/vc_mvp_dec_recon.v:23-83`, `src_dec_dev/vc_mvp_dec_neib_top.v:249-252`.

![Mode, Candidate, reconstruction, and MC mapping](fig3_mode_mv_derivation.svg)

## 4. MC interface and commit ownership

The Decoder MC adapter reuses the existing `mrg2mc` packet shape:

- P8 selects lane 0 with mask `3'b001` and size code 1.
- P16 and P_SKIP select lane 1 with mask `3'b010` and size code 2.
- Lane 2 is unused.
- `dec_mrg2mc_cand_nb = 0`.
- The packet contains valid, picture coordinates, two size fields, reference index, and final MV.
- `mc2mrg_cand_ack` is the MC acknowledgement input.
- `mc_commit = |(rdy & ack)` is the architectural retirement event.
- `dec_mrg2mc_cand_done` is a registered one-cycle pulse after the accepted handshake.
- `cur_cu_upd` is generated from `mc_commit` and carries final MV, reference index, and coordinates into rolling Neighbor state.

While `mc2mrg_cand_ack` is low, `dec_mrg2mc_cand_rdy` remains asserted on the selected lane and the packet/transaction remain stable.

Evidence: `src_dec_dev/vc_mvp_dec_mc_adapter.v:34-104`, `src_dec_dev/vc_mvp_dec_upd_adapter.v:27-54`.

## 5. P8 ordering and Neighbor persistence

```text
S0 -> MC commit/update
   -> S1 -> MC commit/update
        -> S2 -> MC commit/update
             -> S3 -> MC commit/update
```

The next expected P8 sub-index advances only after the preceding sub-block's `mc_commit`. The resulting `cur_cu_upd` updates the rolling Neighbor state used by later sub-blocks.

![P8 serial Neighbor flow](fig2_p8_serial_neighbor_flow.svg)

Evidence: `src_dec_dev/vc_mvp_dec_ctrl.v:226-233`, `src_dec_dev/vc_mvp_dec_upd_adapter.v:27-54`, `src_encoder_ref/vc_mvp_get_neib.v:994-1015`.

## 6. Flush and drain behavior

Slice or mode cancellation is synchronous in the controller, Candidate wrapper, reconstruction block, and MC adapter. MC output is immediately suppressed during flush. A stale MC acknowledgement cannot retire cancelled work.

Neighbor integration tracks physical accepted-but-not-yet-returned A/B reads. Those outstanding counters survive Decoder flush until `rd_lat` responses drain. External ready and qualified Neighbor completion remain blocked until both directions are quiescent.

Evidence: `src_dec_dev/vc_mvp_dec_ctrl.v:157-190`, `src_dec_dev/vc_mvp_dec_cand.v:83-116`, `src_dec_dev/vc_mvp_dec_recon.v:50-83`, `src_dec_dev/vc_mvp_dec_mc_adapter.v:34-104`, `src_dec_dev/vc_mvp_dec_neib_top.v:238-324`.

![Overall hierarchy and ownership](fig1_avc_decoder_mvp_arch.svg)

## 7. Static evidence table

| Finding | Repository evidence |
|---|---|
| Decoder top owns the complete path | `src_dec_dev/vc_mvp_dec_top.v:98-196` |
| Backend owns Neighbor, reconstruction, MC, and update adapters | `src_dec_dev/vc_mvp_dec_backend_top.v:101-228` |
| Real Neighbor hierarchy is instantiated | `src_dec_dev/vc_mvp_dec_neib_top.v:326-407` |
| Real Candidate core is instantiated | `src_dec_dev/vc_mvp_dec_cand.v:54-80` |
| Controller states are DEC_IDLE, DEC_NEIB, DEC_MVP, DEC_RECON, and DEC_SEND | `src_dec_dev/vc_mvp_dec_ctrl.v:56-62` |
| MC acknowledgement retires the transaction | `src_dec_dev/vc_mvp_dec_ctrl.v:147-151`; `src_dec_dev/vc_mvp_dec_mc_adapter.v:68-83` |
| Rolling update is handshake-qualified | `src_dec_dev/vc_mvp_dec_upd_adapter.v:27-54` |
| Neighbor ready and completion use the drain barrier | `src_dec_dev/vc_mvp_dec_neib_top.v:242-261`, `296-324` |

## 8. Verification record

Phase-1 directed RTL verification for T02 and T07 is closed against RTL baseline `3a124096f71b3a6c9ccf04fab52b48f8db8f4ed7` using Synopsys VCS W-2024.09-SP2-2.

### T02 standalone real Candidate

- Normal build: PASS, 15 Candidate transactions, 396000 ps.
- `+define+SYNTHESIS`: PASS, 15 Candidate transactions, 396000 ps.
- Normal CASE 18 emitted exactly one expected overlapping-start `$error` diagnostic.
- `SYNTHESIS` removed that diagnostic as intended.
- Runtime checks covered B0-over-B2 priority, signed MED, only-A1/B1/B0/B2 selection, P8/P16, and P_SKIP spatial selection.

### T07 real-Candidate full pipeline

- Normal build: PASS, 2076000 ps.
- `+define+SYNTHESIS`: PASS, 2076000 ps.
- Results were identical in both builds.

| Event or request | Verified result |
|---|---:|
| accepted | 17 |
| candidate | 16 |
| recon_done | 15 |
| transfer | 14 |
| commit | 14 |
| done | 14 |
| update | 14 |
| lane_done | `{4,10,0}` |
| Neighbor A requests | 20 |
| Neighbor B requests | 17 |
| Col requests | 0 |
| RefList requests | 0 |

Cases A-I covered Candidate behavior, signed reconstruction, P8 serial rolling updates, P_SKIP, MC backpressure, flush cancellation, and stale-ack rejection. These are directed RTL results; this record does not claim full-chip, bitstream-level, formal, coverage-closure, or production signoff.

## 9. Generated artifacts

The generator produces this file, the canonical root pair `../AVC_Decoder_Only_Data_Flow_v1.svg` and `.png`, and these detailed pairs:

- `fig1_avc_decoder_mvp_arch.svg` and `.png`
- `fig2_p8_serial_neighbor_flow.svg` and `.png`
- `fig3_mode_mv_derivation.svg` and `.png`

The retired root mode diagram and the absent `spec_assets` namespace are not generated or canonical.
