# FSM 状态与转移关系清单

本清单由优化前的 `figures/fsm_*.dot` 机械提取并人工复核。`reset` 圆点和说明框不计入状态数量；下列状态名、方向及标签是新版图的语义核对基线。

## `fsm_amvp_term`

- 状态数量：3
- 状态：`TERM_IDLE`、`TERM_WAIT_EMPTY`、`TERM_FLUSH`
- 初始状态：`TERM_IDLE`
- 完成阶段：`TERM_FLUSH`（完成后返回 `TERM_IDLE`，不是吸收态）

```text
reset -> TERM_IDLE : "!vc_rst_z or reg_slice_go"
TERM_IDLE -> TERM_WAIT_EMPTY : "|cur_cu_start && cur_cu_terminate"
TERM_IDLE -> TERM_IDLE : "otherwise"
TERM_WAIT_EMPTY -> TERM_FLUSH : "all_queue_empty"
TERM_WAIT_EMPTY -> TERM_WAIT_EMPTY : "!all_queue_empty"
TERM_FLUSH -> TERM_IDLE : "gt0 == 0"
TERM_FLUSH -> TERM_FLUSH : "gt0 != 0"
```

## `fsm_cand_gen_amvp`

- 状态数量：5
- 状态：`CAND_IDLE`、`CAND_WAIT_SCALE_A`、`CAND_WAIT_SCALE_B`、`CAND_WAIT_SCALE_C`、`CAND_DONE`
- 初始状态：`CAND_IDLE`
- 完成状态：`CAND_DONE`（下一拍无条件返回 `CAND_IDLE`）

```text
reset -> CAND_IDLE : "!vc_rst_z or reg_slice_go"
CAND_IDLE -> CAND_IDLE : "!cand_cu_start"
CAND_IDLE -> CAND_WAIT_SCALE_A : "cand_cu_start && scaled-A selected"
CAND_IDLE -> CAND_WAIT_SCALE_B : "cand_cu_start && scaled-B selected"
CAND_IDLE -> CAND_WAIT_SCALE_C : "cand_cu_start && scaled-C selected"
CAND_IDLE -> CAND_DONE : "cand_cu_start && no scale wait required"
CAND_WAIT_SCALE_A -> CAND_WAIT_SCALE_A : "!scale_done"
CAND_WAIT_SCALE_A -> CAND_WAIT_SCALE_C : "scale_done && next selected source is scaled-C"
CAND_WAIT_SCALE_A -> CAND_DONE : "scale_done && no scaled-C continuation"
CAND_WAIT_SCALE_B -> CAND_WAIT_SCALE_B : "!scale_done"
CAND_WAIT_SCALE_B -> CAND_WAIT_SCALE_C : "scale_done && next selected source is scaled-C"
CAND_WAIT_SCALE_B -> CAND_DONE : "scale_done && no scaled-C continuation"
CAND_WAIT_SCALE_C -> CAND_WAIT_SCALE_C : "!scale_done"
CAND_WAIT_SCALE_C -> CAND_DONE : "scale_done"
CAND_DONE -> CAND_IDLE : "unconditional"
```

## `fsm_cand_gen_merge`

- 状态数量：3
- 状态：`CAND_IDLE`、`CAND_WAIT_SCALE_C`、`CAND_DONE`
- 初始状态：`CAND_IDLE`
- 完成状态：`CAND_DONE`（下一拍无条件返回 `CAND_IDLE`）

```text
reset -> CAND_IDLE : "!vc_rst_z or reg_slice_go"
CAND_IDLE -> CAND_IDLE : "!cand_cu_start"
CAND_IDLE -> CAND_WAIT_SCALE_C : "cand_cu_start && selected temporal candidate needs scaling"
CAND_IDLE -> CAND_DONE : "cand_cu_start && no scale wait required"
CAND_WAIT_SCALE_C -> CAND_WAIT_SCALE_C : "!scale_done"
CAND_WAIT_SCALE_C -> CAND_DONE : "scale_done"
CAND_DONE -> CAND_IDLE : "unconditional"
```

## `fsm_mrg_flow`

- 状态数量：8（candidate 0 与 candidate 1 各 4 个独立状态实例）
- candidate 0 状态：`MRG_IDLE`、`MRG_CAND_RDY`、`MRG_MC_CAND_RDY`、`MRG_DONE`
- candidate 1 状态：`MRG_IDLE`、`MRG_CAND_RDY`、`MRG_MC_CAND_RDY`、`MRG_DONE`
- 初始状态：两个实例均为 `MRG_IDLE`
- 完成状态：两个实例均为 `MRG_DONE`，随后按各自条件返回 `MRG_IDLE`

```text
candidate0.reset -> candidate0.MRG_IDLE : "!vc_rst_z"
candidate0.MRG_IDLE -> candidate0.MRG_CAND_RDY : "cand_rdy && blk_en"
candidate0.MRG_IDLE -> candidate0.MRG_IDLE : "otherwise"
candidate0.MRG_CAND_RDY -> candidate0.MRG_MC_CAND_RDY : "mrg2mc_cand_hsk"
candidate0.MRG_CAND_RDY -> candidate0.MRG_CAND_RDY : "!mrg2mc_cand_hsk"
candidate0.MRG_MC_CAND_RDY -> candidate0.MRG_DONE : "mc2mrg_cost_hsk"
candidate0.MRG_MC_CAND_RDY -> candidate0.MRG_MC_CAND_RDY : "!mc2mrg_cost_hsk"
candidate0.MRG_DONE -> candidate0.MRG_IDLE : "!cand_diff || candidate1_done"
candidate0.MRG_DONE -> candidate0.MRG_DONE : "cand_diff && !candidate1_done"

candidate1.reset -> candidate1.MRG_IDLE : "!vc_rst_z"
candidate1.MRG_IDLE -> candidate1.MRG_CAND_RDY : "cand_rdy && blk_en"
candidate1.MRG_IDLE -> candidate1.MRG_IDLE : "otherwise"
candidate1.MRG_CAND_RDY -> candidate1.MRG_IDLE : "!cand_diff"
candidate1.MRG_CAND_RDY -> candidate1.MRG_CAND_RDY : "cand_diff && candidate0_CAND_RDY"
candidate1.MRG_CAND_RDY -> candidate1.MRG_MC_CAND_RDY : "cand_diff && !candidate0_CAND_RDY && mrg2mc_cand_hsk"
candidate1.MRG_CAND_RDY -> candidate1.MRG_CAND_RDY : "cand_diff && !candidate0_CAND_RDY && !mrg2mc_cand_hsk"
candidate1.MRG_MC_CAND_RDY -> candidate1.MRG_MC_CAND_RDY : "candidate0_MC_CAND_RDY"
candidate1.MRG_MC_CAND_RDY -> candidate1.MRG_DONE : "!candidate0_MC_CAND_RDY && mc2mrg_cost_hsk"
candidate1.MRG_MC_CAND_RDY -> candidate1.MRG_MC_CAND_RDY : "!candidate0_MC_CAND_RDY && !mc2mrg_cost_hsk"
candidate1.MRG_DONE -> candidate1.MRG_IDLE : "unconditional"
```

## `fsm_mrg_mc_done`

- 状态数量：4
- 状态：`MC_IDLE`、`MC_WAIT_HSK_0`、`MC_WAIT_HSK_1`、`MC_DONE`
- 初始状态：`MC_IDLE`
- 完成状态：`MC_DONE`（下一拍无条件返回 `MC_IDLE`）
- `E/C1/F0/H/D` 框为条件缩写说明，不是状态

```text
reset -> MC_IDLE : "!vc_rst_z\n(or slice reset for active lane)"
MC_IDLE -> MC_IDLE : "!E"
MC_IDLE -> MC_WAIT_HSK_1 : "E && C1 && (F0 || H)"
MC_IDLE -> MC_WAIT_HSK_0 : "E && C1 && !F0 && !H"
MC_IDLE -> MC_DONE : "E && !C1 && (F0 || H)"
MC_IDLE -> MC_WAIT_HSK_0 : "E && !C1 && !F0 && !H"
MC_WAIT_HSK_0 -> MC_WAIT_HSK_0 : "!H"
MC_WAIT_HSK_0 -> MC_WAIT_HSK_1 : "H && D"
MC_WAIT_HSK_0 -> MC_DONE : "H && !D"
MC_WAIT_HSK_1 -> MC_WAIT_HSK_1 : "!H"
MC_WAIT_HSK_1 -> MC_DONE : "H"
MC_DONE -> MC_IDLE : "unconditional"
```

条件缩写原文：

```text
E = reg_avc_mode ? mrg2mc_cand_rdy[i]
    : (cand_rdy[1] && blk_en[i])
C1 = cand1_ena[i]
F0 = candidate0 flow in MRG_MC_CAND_RDY
H = mrg2mc_cand_hsk[i]
D = cand_diff[i]
```

## `fsm_mrg_mv_gain`

- 状态数量：4
- 状态：`MVG_IDLE`、`MVG_BLK8`、`MVG_BLK16`、`MVG_BLK32`
- 初始状态：`MVG_IDLE`
- 无独立 DONE 状态；各 block 状态按计数及队列条件前进或返回 `MVG_IDLE`

```text
reset -> MVG_IDLE : "!vc_rst_z or reg_slice_go"
MVG_IDLE -> MVG_BLK16 : "reg_avc_mode && cand_push[2]"
MVG_IDLE -> MVG_BLK8 : "!reg_avc_mode && cand_push[1]"
MVG_IDLE -> MVG_IDLE : "otherwise"
MVG_BLK8 -> MVG_BLK8 : "mvg_cnt != 5"
MVG_BLK8 -> MVG_BLK16 : "mvg_cnt==5 && cu_empty_n_reg[1]"
MVG_BLK8 -> MVG_IDLE : "mvg_cnt==5 && !cu_empty_n_reg[1]"
MVG_BLK16 -> MVG_BLK16 : "mvg_cnt != 5"
MVG_BLK16 -> MVG_IDLE : "mvg_cnt==5 && (reg_avc_mode || !cu_empty_n_reg[2])"
MVG_BLK16 -> MVG_BLK32 : "mvg_cnt==5 && !reg_avc_mode && cu_empty_n_reg[2]"
MVG_BLK32 -> MVG_BLK32 : "mvg_cnt != 5"
MVG_BLK32 -> MVG_IDLE : "mvg_cnt == 5"
```

## `fsm_mrg_term`

- 状态数量：3
- 状态：`TERM_IDLE`、`TERM_WAIT_EMPTY`、`TERM_FLUSH`
- 初始状态：`TERM_IDLE`
- 完成阶段：`TERM_FLUSH`（完成后返回 `TERM_IDLE`，不是吸收态）

```text
reset -> TERM_IDLE : "!vc_rst_z or reg_slice_go"
TERM_IDLE -> TERM_WAIT_EMPTY : "!(|cur_cu_start) && cur_cu_terminate"
TERM_IDLE -> TERM_IDLE : "otherwise"
TERM_WAIT_EMPTY -> TERM_FLUSH : "all_queue_empty"
TERM_WAIT_EMPTY -> TERM_WAIT_EMPTY : "!all_queue_empty"
TERM_FLUSH -> TERM_IDLE : "gt0 == 0"
TERM_FLUSH -> TERM_FLUSH : "gt0 != 0"
```

## `fsm_mvp_ctrl_amvp`

- 状态数量：7
- 状态：`AMVP_IDLE`、`AMVP_WAIT_CU_START`、`AMVP_WAIT_NEIB_DONE`、`AMVP_CAND_BLK8`、`AMVP_CAND_BLK16`、`AMVP_CAND_BLK32`、`AMVP_BLK_DONE`
- 初始状态：`AMVP_IDLE`
- 完成状态：`AMVP_BLK_DONE`，随后按参考列表与 CTU 坐标返回不同阶段

```text
reset -> AMVP_IDLE : "!vc_rst_z or reg_slice_go"
AMVP_IDLE -> AMVP_WAIT_CU_START : "cur_ctu_start && !reg_i_slice"
AMVP_IDLE -> AMVP_IDLE : "otherwise"
AMVP_WAIT_CU_START -> AMVP_WAIT_NEIB_DONE : "|empty_n"
AMVP_WAIT_CU_START -> AMVP_WAIT_CU_START : "!|empty_n"
AMVP_WAIT_NEIB_DONE -> AMVP_CAND_BLK8 : "neib_done_con"
AMVP_WAIT_NEIB_DONE -> AMVP_WAIT_NEIB_DONE : "!neib_done_con"
AMVP_CAND_BLK8 -> AMVP_CAND_BLK8 : "!cand_blk_done"
AMVP_CAND_BLK8 -> AMVP_CAND_BLK16 : "cand_blk_done && empty_n[1]"
AMVP_CAND_BLK8 -> AMVP_CAND_BLK32 : "cand_blk_done && !empty_n[1] && empty_n[2]"
AMVP_CAND_BLK8 -> AMVP_BLK_DONE : "cand_blk_done && !empty_n[1] && !empty_n[2]"
AMVP_CAND_BLK16 -> AMVP_CAND_BLK16 : "!cand_blk_done"
AMVP_CAND_BLK16 -> AMVP_CAND_BLK32 : "cand_blk_done && empty_n[2]"
AMVP_CAND_BLK16 -> AMVP_BLK_DONE : "cand_blk_done && !empty_n[2]"
AMVP_CAND_BLK32 -> AMVP_CAND_BLK32 : "!cand_blk_done"
AMVP_CAND_BLK32 -> AMVP_BLK_DONE : "cand_blk_done"
AMVP_BLK_DONE -> AMVP_WAIT_NEIB_DONE : "!(&chk_ref_done)"
AMVP_BLK_DONE -> AMVP_IDLE : "&chk_ref_done && cux==7 && cuy==7"
AMVP_BLK_DONE -> AMVP_WAIT_CU_START : "&chk_ref_done && !(cux==7 && cuy==7)"
```

## `fsm_mvp_ctrl_merge`

- 状态数量：7
- 状态：`AMVP_IDLE`、`AMVP_WAIT_CU_START`、`AMVP_WAIT_NEIB_DONE`、`AMVP_CAND_BLK8`、`AMVP_CAND_BLK16`、`AMVP_CAND_BLK32`、`AMVP_BLK_DONE`
- 初始状态：`AMVP_IDLE`
- 完成状态：`AMVP_BLK_DONE`，随后按 CTU 坐标返回 `AMVP_IDLE` 或 `AMVP_WAIT_CU_START`

```text
reset -> AMVP_IDLE : "!vc_rst_z or reg_slice_go"
AMVP_IDLE -> AMVP_WAIT_CU_START : "cur_ctu_start && !reg_i_slice"
AMVP_IDLE -> AMVP_IDLE : "otherwise"
AMVP_WAIT_CU_START -> AMVP_WAIT_NEIB_DONE : "|empty_n"
AMVP_WAIT_CU_START -> AMVP_WAIT_CU_START : "!|empty_n"
AMVP_WAIT_NEIB_DONE -> AMVP_CAND_BLK8 : "neib_done_con"
AMVP_WAIT_NEIB_DONE -> AMVP_WAIT_NEIB_DONE : "!neib_done_con"
AMVP_CAND_BLK8 -> AMVP_CAND_BLK8 : "!cand_blk_done"
AMVP_CAND_BLK8 -> AMVP_CAND_BLK16 : "cand_blk_done && empty_n[1]"
AMVP_CAND_BLK8 -> AMVP_CAND_BLK32 : "cand_blk_done && !empty_n[1] && empty_n[2]"
AMVP_CAND_BLK8 -> AMVP_BLK_DONE : "cand_blk_done && !empty_n[1] && !empty_n[2]"
AMVP_CAND_BLK16 -> AMVP_CAND_BLK16 : "!cand_blk_done"
AMVP_CAND_BLK16 -> AMVP_CAND_BLK32 : "cand_blk_done && empty_n[2]"
AMVP_CAND_BLK16 -> AMVP_BLK_DONE : "cand_blk_done && !empty_n[2]"
AMVP_CAND_BLK32 -> AMVP_CAND_BLK32 : "!cand_blk_done"
AMVP_CAND_BLK32 -> AMVP_BLK_DONE : "cand_blk_done"
AMVP_BLK_DONE -> AMVP_IDLE : "cux==7 && cuy==7"
AMVP_BLK_DONE -> AMVP_WAIT_CU_START : "otherwise"
```

## `fsm_neib_tracker`

- 状态数量：2
- 状态：`NEIB_IDLE`、`NEIB_WAIT_DONE`
- 初始状态：`NEIB_IDLE`
- 无独立 DONE 状态；邻居处理完成后从 `NEIB_WAIT_DONE` 返回 `NEIB_IDLE`

```text
reset -> NEIB_IDLE : "!vc_rst_z or reg_slice_go"
NEIB_IDLE -> NEIB_WAIT_DONE : "cmdq_cu_start"
NEIB_IDLE -> NEIB_IDLE : "!cmdq_cu_start"
NEIB_WAIT_DONE -> NEIB_IDLE : "neib_done_con"
NEIB_WAIT_DONE -> NEIB_WAIT_DONE : "!neib_done_con"
```

## `fsm_rd_mem`

- 状态数量：3
- 状态：`MEM_IDLE`、`MEM_GET`、`MEM_CHK_DQ`
- 初始状态：`MEM_IDLE`
- 无独立 DONE 状态；`MEM_CHK_DQ` 在队列排空后返回 `MEM_IDLE`

```text
reset -> MEM_IDLE : "!vc_rst_z or reg_slice_go"
MEM_IDLE -> MEM_GET : "ip_cu_start"
MEM_IDLE -> MEM_IDLE : "!ip_cu_start"
MEM_GET -> MEM_CHK_DQ : "last_hsk = (mem_cnt==mem_avail_cnt-1) && mem2ip_gnt"
MEM_GET -> MEM_GET : "!last_hsk"
MEM_CHK_DQ -> MEM_IDLE : "!n_empty_n"
MEM_CHK_DQ -> MEM_CHK_DQ : "n_empty_n"
```

## `fsm_scale`

- 状态数量：2
- 状态：`MULCYC_IDLE`、`MULCYC_ACT`
- 初始状态：`MULCYC_IDLE`
- 无独立 DONE 状态；多周期计数完成后从 `MULCYC_ACT` 返回 `MULCYC_IDLE`

```text
reset -> MULCYC_IDLE : "!vc_rst_z or reg_slice_go"
MULCYC_IDLE -> MULCYC_ACT : "scale_start"
MULCYC_IDLE -> MULCYC_IDLE : "!scale_start"
MULCYC_ACT -> MULCYC_IDLE : "mul_cyc_cnt == MULCYC"
MULCYC_ACT -> MULCYC_ACT : "mul_cyc_cnt != MULCYC"
```
