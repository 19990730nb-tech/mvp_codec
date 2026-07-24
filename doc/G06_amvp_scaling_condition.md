# G06 AMVP Scaling Condition

## 1. Case Definition

| 项目 | 内容 |
|---|---|
| Case ID | G06 |
| Mode | AMVP |
| Block Size | blk8 或 blk16 |
| AVC mode | 0 |
| 是否需要 scaling | Yes |
| 是否边界 case | No，优先非边界 |
| 主要验证点 | AMVP 中 scaled candidate path，包括 `scale_start/scale_done/scale_mvx/scale_mvy` 与 scaled candidate 输出 |

## 2. 必须满足的触发条件

| 条件 | 判定方式 |
|---|---|
| AMVP path 有效 | `amvp_cand_cu_start == 1` 或 AMVP candidate FSM 从 IDLE 跳转 |
| 非 AVC mode | `reg_avc_mode == 0` |
| 非 I slice | `reg_i_slice == 0` |
| block size | `amvp_blk_sz[0] == 1` 或 `amvp_blk_sz[1] == 1` |
| scaling 被触发 | `scale_start == 1` |
| scaling 正常完成 | `scale_done == 1` |
| FSM 进入等待缩放状态 | `fsm_cand_cs` 进入 `CAND_WAIT_SCALE_A/B/C` 中至少一个 |
| scaled MV 有效 | `scale_mvx/scale_mvy` 在 `scale_done` 后稳定 |
| candidate 正常完成 | `amvp_cand_rdy == 1` 且 `amvp_cand_blk_done == 1` |

## 3. 建议优先选择的条件

| 条件 | 说明 |
|---|---|
| 优先 spatial scaling | 如果能触发 A/B scaled path，优先用于验证 AMVP spatial scaling |
| 其次 temporal scaling | 若只有 C-side scaled path 可用，也可作为 G06 |
| `col_poc_diff != 0` | 上层已审查保证不会为 0；记录时仍建议保存相关 POC diff 信号 |
| 非边界 | 避免与 boundary fallback 混淆 |

## 4. 需要重点记录的信号

| 类别 | 信号 |
|---|---|
| Trigger | `amvp_cand_cu_start`, `amvp_blk_sz`, `reg_avc_mode`, `reg_i_slice` |
| Coordinate | `cur_cu_x`, `cur_cu_y`, `cur_ctu_x`, `cur_ctu_y` |
| Neighbor / Ref | `amvp_neib_a`, `amvp_neib_b`, `amvp_col_c`, `amvp_col_c_avail`, `reflist_info` |
| Candidate mask | `cand_a`, `cand_b`, `cand_c` |
| FSM | `fsm_cand_cs`, `fsm_cand_ns` |
| Scale control | `scale_start`, `scale_done` |
| Scale output | `scale_mvx`, `scale_mvy` |
| Optional scale operands | `n_cur_poc_diff`, `sel_poc_diff`，如果工具允许观察内部 wire |
| Selection | `cand0_sel_onehot`, `cand1_sel_onehot` |
| Output | `amvp_cand_mv`, `amvp_cand_rdy`, `amvp_cand_blk_done` |

## 5. 有效性判定

| 编号 | 判定标准 |
|---|---|
| 1 | AMVP candidate generation 被启动 |
| 2 | `reg_avc_mode == 0` |
| 3 | 当前不是 I slice |
| 4 | `scale_start == 1` |
| 5 | FSM 进入 scaling wait state |
| 6 | `scale_done == 1` |
| 7 | `scale_mvx/scale_mvy` 被用于 `cand_mv[0]` 或 `cand_mv[1]` |
| 8 | candidate generation 正常完成 |
| 9 | 该 case 不作为基础 unscaled path、AVC median 或 Merge 行为依据 |

## 6. 暂不要求

| 不要求项 | 原因 |
|---|---|
| blk8/blk16 基础 unscaled path | G01/G02 单独覆盖 |
| AVC median predictor | G05 单独覆盖 |
| Merge scaling | 后续如需要再单独扩展 |
| td==0 保护验证 | 上层已审查保证 `td != 0`，本 case 只验证正常 scaling path |
