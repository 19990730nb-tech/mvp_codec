# T00 — AVC Decoder Transaction Controller (Luna Implementation Task)

## 0. Role of this task

Implement only the **decoder-side transaction/admission controller** for AVC MVP.

This task does **not** implement neighbor address generation, AVC median arithmetic, final-MV arithmetic, CCU output packing, MC, MVB DMA writeback, or encoder behavior changes.

The controller is a new standalone module so that decoder scheduling can be validated before integration into the existing encoder-derived hierarchy.

Suggested new file:

```text
vc_mvp_dec_ctrl.v
```

Do not modify existing encoder RTL in T00 unless required only to compile a standalone unit test; if any existing file must be touched, stop and report why before changing it.

---

## 1. Golden RTL evidence

Use the following files as source of truth. Do not infer decoder behavior from old decoder attempts.

### 1.1 `vc_mvp_cand_gen.v`

AVC candidate generation is immediate from `CAND_IDLE` when `cand_cu_start` is asserted:

```verilog
// around L1094-L1097
fsm_cand_cs[CAND_IDLE]: begin
    if(cand_cu_start) begin
        if(cand_ua_ub_con | reg_avc_mode)
            fsm_cand_ns[CAND_DONE] = 1;
```

The AVC one-hot candidate select is also generated in the **same CAND_IDLE/cand_cu_start cycle**:

```verilog
// around L1212-L1220
fsm_cand_cs[CAND_IDLE]: begin
    if(cand_cu_start) begin
        if(cand_ua_ub_con | reg_avc_mode) begin
            ...
            cand0_sel_onehot[MED] = 1;
```

`cand_blk_done` is not the candidate capture event; it is high in the following `CAND_DONE` state:

```verilog
// around L199
assign cand_blk_done = fsm_cand_cs[CAND_DONE];
```

**T00 rule:** the integration layer must capture the AVC MVP in the `dec_cand_start && cand_rdy[0]` cycle. Do not wait for `cand_blk_done` to capture `cand_mv[0]`.

### 1.2 `vc_mvp_get_neib.v`

Neighbor completion is already abstracted as `neib_done_amvp`:

```verilog
// around L402-L411
assign neib_done_con = (get_neib_a_idle | blk_8_start_a_con) &
                       (get_neib_b_idle | blk_8_start_b_con) &
                        get_neib_c_idle & get_ref_idle;
assign neib_done_amvp = neib_done_con;
```

Current-CU final motion information updates the intra-CU rolling registers on `cur_cu_upd`:

```verilog
// around L995-L1000
if(cur_cu_upd) begin
    if(cur_cu_upd_sz == 2'd1) begin // blk8
        if(cur_cu_upd_y[0]==1'b0)
            b_0_reg[cur_cu_upd_x[1:0]] <= cur_cu_upd_cand;
        if(cur_cu_upd_x[0]==1'b0)
            a_0_reg[cur_cu_upd_y[1:0]] <= cur_cu_upd_cand;
```

**T00 rule:** for P8x8, the next sub-block must not be admitted until the previous sub-block's matching `cur_cu_upd` commit has occurred.

### 1.3 `vc_mvp_ctrl.v`

The encoder controller contains block scheduling and reference traversal, e.g. `cur_ref_idx_r` increments after candidate completion:

```verilog
// around L432-L442
reg [3:0] cur_ref_idx_r;
...
else if(cand_blk_done & (&cur_ref_upd)) begin
    if(cur_ref_idx_r == num_ref_m1)
        cur_ref_idx_r <= 0;
    else
        cur_ref_idx_r <= cur_ref_idx_r + 1;
end
```

**T00 rule:** do not reuse or reproduce this encoder reference traversal in the decoder controller. Decoder `ref_idx` comes directly from CCU syntax input.

---

## 2. Decoder CCU→IRPU interface contract

The decoder receives one motion transaction only when:

```verilog
dec_accept = ccu2irpu_valid && irpu2ccu_rdy;
```

New top-level decoder syntax signals are:

```verilog
input                  ccu2irpu_valid;
output                 irpu2ccu_rdy;
input  [1:0][15:0]     ccu2irpu_mvd;
input  [3:0]           ccu2irpu_ref_idx;
input                  ccu2irpu_is_skip;
input                  ccu2irpu_part_mode;   // 0: P16x16, 1: P8x8
input  [1:0]           ccu2irpu_sub_idx;     // P8: 0,1,2,3
```

All syntax payload must be latched on `dec_accept`. After that cycle, decoder logic must use only the latched copies.

For T00, also accept the already-derived current transaction coordinates from the integration layer:

```verilog
input [2:0] dec_txn_cux;
input [2:0] dec_txn_cuy;
```

Do **not** invent how `sub_idx` maps to `cux/cuy` in this task. That mapping is an integration task.

---

## 3. One-entry blocking admission policy

First implementation must be deliberately conservative:

```verilog
assign irpu2ccu_rdy = codec_mode && dec_fsm_cs[DEC_IDLE];
```

where `codec_mode==1` means decoder operation.

`DEC_IDLE` means there is no accepted but uncommitted decoder motion transaction.

No input FIFO. No speculative acceptance. No accepting S(n+1) before S(n) commit.

---

## 4. Required FSM

Use exactly these six architectural states. Encoding may be one-hot or binary according to local RTL style, but state meaning must remain unchanged.

```text
DEC_IDLE
   |
   | dec_accept
   v
DEC_NEIB
   |
   | neib_done_amvp
   v
DEC_MVP
   |
   | cand_capture_done
   v
DEC_RECON
   |
   | recon_done
   v
DEC_SEND
   |
   | result_accept
   v
DEC_WAIT_UPD
   |
   | matching cur_cu_upd commit
   v
DEC_IDLE
```

### State contract

| State | Required action | Exit condition | `irpu2ccu_rdy` |
|---|---|---|---:|
| `DEC_IDLE` | wait for and latch one CCU syntax transaction | `dec_accept` | 1 |
| `DEC_NEIB` | issue exactly one neighbor-start pulse for the latched transaction, then wait | `neib_done_amvp` | 0 |
| `DEC_MVP` | issue exactly one candidate-start pulse; AVC MVP must be captured in this start cycle | `cand_capture_done` | 0 |
| `DEC_RECON` | start final-MV reconstruction | `recon_done` | 0 |
| `DEC_SEND` | hold decoded result pending downstream acceptance | `result_accept` | 0 |
| `DEC_WAIT_UPD` | wait until the same transaction is committed through `cur_cu_upd` | `dec_commit` | 0 |

---

## 5. Pulse generation requirements

The controller must generate single-cycle pulses:

```verilog
output dec_neib_start;
output dec_cand_start;
output dec_recon_start;
```

### `dec_neib_start`

Must occur **one cycle after `dec_accept`**, after transaction fields are registered. Do not start neighbor fetch combinationally in the accept cycle using raw CCU inputs.

A valid implementation style is a registered pulse:

```verilog
dec_neib_start_q <= dec_accept;
```

with appropriate reset/default clearing.

### `dec_cand_start`

Must occur once after `neib_done_amvp`. It must not remain high while waiting in `DEC_MVP`.

The integration layer will define:

```verilog
cand_capture_done = dec_cand_start && cand_rdy[0];
```

because the AVC candidate is combinationally valid in the `cand_cu_start` cycle.

### `dec_recon_start`

Must occur once after the MVP capture event.

---

## 6. Latched transaction registers

At minimum implement registered copies:

```verilog
reg [1:0][15:0] dec_mvd_q;
reg [3:0]       dec_ref_idx_q;
reg             dec_is_skip_q;
reg             dec_part_mode_q;
reg [1:0]       dec_sub_idx_q;
reg [2:0]       dec_cux_q;
reg [2:0]       dec_cuy_q;
```

Latch all only on `dec_accept`.

Export these registered fields to later datapath/integration tasks.

Do not use raw `ccu2irpu_*` payload after handshake.

---

## 7. P8x8 ordering tracker

Implement:

```verilog
reg [1:0] dec_expected_sub_idx;
```

Reset value: `2'd0`.

Do **not** advance it on `dec_accept`.

Advance only on a successful matching `dec_commit`:

```text
commit S0 -> expected = 1
commit S1 -> expected = 2
commit S2 -> expected = 3
commit S3 -> expected = 0
```

P16x16/skip transaction completion leaves/resets expected index at 0.

The expected index is a protocol checker, not a resource-ready condition.

Do **not** implement:

```verilog
irpu2ccu_rdy = idle && (ccu2irpu_sub_idx == dec_expected_sub_idx);
```

Reason: a protocol error must not create a valid/ready deadlock.

Use simulation assertions/errors instead.

---

## 8. Commit matching

The controller must not leave `DEC_WAIT_UPD` on an unrelated `cur_cu_upd` pulse.

Inputs:

```verilog
input        cur_cu_upd;
input [1:0]  cur_cu_upd_sz;
input [2:0]  cur_cu_upd_x;
input [2:0]  cur_cu_upd_y;
```

Expected size:

```text
P8x8   -> 2'd1
P16x16 -> 2'd2
P_SKIP -> 2'd2
```

Create a match equivalent to:

```verilog
dec_commit = cur_cu_upd
          && (cur_cu_upd_sz == expected_sz)
          && (cur_cu_upd_x  == dec_cux_q)
          && (cur_cu_upd_y  == dec_cuy_q);
```

Only `dec_commit` may release `DEC_WAIT_UPD`.

---

## 9. External completion inputs for T00

T00 does not implement the downstream blocks. Model their completion events as controller inputs:

```verilog
input neib_done_amvp;
input cand_capture_done;
input recon_done;
input result_accept;
```

Do not guess or hard-wire the eventual physical CCU result interface in T00.

Later integration tasks will map:

```text
neib_done_amvp  <- vc_mvp_get_neib
cand_capture_done <- dec_cand_start & vc_mvp_cand_gen.cand_rdy[0]
recon_done      <- decoder final-MV datapath
result_accept   <- chosen CCU result-path handshake
```

---

## 10. Required protocol assertions (`ifndef SYNTHESIS`)

Add simulation-only checks. At minimum:

1. P8 accepted `sub_idx` must equal `dec_expected_sub_idx`.
2. P16 transaction must use `sub_idx==0`.
3. P_SKIP must be P16 (`part_mode==0`) and `sub_idx==0`.
4. `dec_cand_start` must be a single-cycle pulse.
5. `dec_neib_start` must be a single-cycle pulse.
6. `dec_recon_start` must be a single-cycle pulse.
7. `dec_commit` must only be acted on in `DEC_WAIT_UPD`.
8. No accepted transaction while controller is busy (should follow from `rdy`, assertion still useful).

Assertions must not alter synthesized behavior.

---

## 11. Explicitly forbidden in T00

Do not:

- modify encoder `vc_mvp_ctrl` scheduling;
- implement any `ref_idx` traversal;
- use `vc_mvp_cand_prior` for AVC ref/POC matching;
- implement temporal/colocated MVP;
- implement FME/IME;
- implement MC/RDO/SATD logic;
- implement MVB SRAM writeback;
- implement `MVP + MVD` arithmetic yet;
- implement P_SKIP median/zero-motion arithmetic yet;
- add an input FIFO;
- allow more than one outstanding decoder transaction;
- change existing encoder behavior.

---

## 12. Suggested module interface

Use this as the target shape; minor naming adjustments are allowed only if required by project style.

```verilog
module vc_mvp_dec_ctrl (
    input                   clk_vc,
    input                   vc_rst_z,
    input                   codec_mode,

    input                   ccu2irpu_valid,
    output                  irpu2ccu_rdy,
    input      [1:0][15:0]  ccu2irpu_mvd,
    input      [3:0]        ccu2irpu_ref_idx,
    input                   ccu2irpu_is_skip,
    input                   ccu2irpu_part_mode,
    input      [1:0]        ccu2irpu_sub_idx,

    input      [2:0]        dec_txn_cux,
    input      [2:0]        dec_txn_cuy,

    input                   neib_done_amvp,
    input                   cand_capture_done,
    input                   recon_done,
    input                   result_accept,

    input                   cur_cu_upd,
    input      [1:0]        cur_cu_upd_sz,
    input      [2:0]        cur_cu_upd_x,
    input      [2:0]        cur_cu_upd_y,

    output                  dec_neib_start,
    output                  dec_cand_start,
    output                  dec_recon_start,

    output     [1:0][15:0]  dec_mvd,
    output     [3:0]        dec_ref_idx,
    output                  dec_is_skip,
    output                  dec_part_mode,
    output     [1:0]        dec_sub_idx,
    output     [2:0]        dec_cux,
    output     [2:0]        dec_cuy,

    output     [1:0]        dec_expected_sub_idx,
    output                  dec_busy,
    output     [5:0]        dbg_dec_fsm_cs
);
```

`dbg_dec_fsm_cs` may expose a one-hot six-state register. If binary encoding is used, change debug width accordingly and document it.

---

## 13. Directed verification required before delivery

At minimum create a small self-checking testbench or compile-time/simulation harness for these sequences.

### Case A — P16 normal

```text
accept P16/sub0
-> one neib_start pulse
-> neib_done
-> one cand_start pulse
-> cand_capture_done
-> one recon_start pulse
-> recon_done
-> result_accept
-> unrelated cur_cu_upd must NOT release
-> matching blk16 cur_cu_upd releases to IDLE
```

### Case B — P8 S0→S3

For each sub-block:

```text
accept S(n)
-> busy/rdy=0
-> complete all stages
-> matching cur_cu_upd
-> expected_sub_idx advances
-> only then rdy=1 for S(n+1)
```

After S3 commit, expected index returns to 0.

### Case C — backpressure

Hold any one of:

```text
neib_done_amvp=0
cand_capture_done=0
recon_done=0
result_accept=0
matching cur_cu_upd absent
```

for multiple cycles. Controller must remain in the corresponding state and must keep `irpu2ccu_rdy=0`.

### Case D — invalid P8 order

Present `sub_idx=2` when expected is 0. Handshake may still occur because ready is resource-based, but simulation must report a protocol error. It must not deadlock the interface.

### Case E — P_SKIP

Accept `is_skip=1, part_mode=0, sub_idx=0`. Controller flow remains the same; arithmetic differences are deferred to later tasks.

---

## 14. Deliverables

Return exactly:

1. new `vc_mvp_dec_ctrl.v`;
2. testbench/harness used for T00;
3. compile command and compile result;
4. simulation result for Cases A-E;
5. concise diff/file summary;
6. any ambiguity discovered in source RTL — do not silently resolve it by redesigning the architecture.

Do not start T01 or integration work in the same task.
