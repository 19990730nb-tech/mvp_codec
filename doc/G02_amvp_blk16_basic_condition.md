# G02 AMVP blk16 Basic Condition

## 1. Case Definition

| 项目 | 内容 |
|---|---|
| Case ID | G02 |
| Mode | AMVP |
| Block Size | blk16 |
| AVC mode | 0 |
| 是否需要 scaling | No，优先选择 `scale_start=0` 的 unscaled path；若 `scale_start=1`，该片段归入 G06 |
| 是否边界 case | No |
| 主要验证点 | 普通非边界、A/B 均可用时，blk16 AMVP neighbor 选择与 `cand_mv[0]/cand_mv[1]` 基础生成 |

## 2. 必须满足的触发条件

| 条件 | 判定方式 |
|---|---|
| AMVP path 有效 | `amvp_cand_cu_start == 1` 或 AMVP candidate FSM 从 IDLE 跳转 |
| blk16 | `amvp_blk_sz[1] == 1` |
| 非 AVC mode | `reg_avc_mode == 0` |
| 非 I slice | `reg_i_slice == 0` |
| 非边界 | `cur_cu_a_avail != 0` 且 `cur_cu_b_avail != 0` |
| A/B neighbor 均可用 | `amvp_cmd_out` 中 A/B availability 不全为 0，且 `amvp_neib_a/amvp_neib_b` 有有效 payload |
| 不走 scaling | `scale_start == 0` |
| candidate 正常完成 | `amvp_cand_rdy == 1` 且 `amvp_cand_blk_done == 1` |

## 3. 建议优先选择的坐标

| 坐标 | 说明 |
|---|---|
| `cur_cu_x = 2` 或 `4` | 避免左边界，并落在 CTU 内部 |
| `cur_cu_y = 2` 或 `4` | 避免上边界，并落在 CTU 内部 |
| `cur_ctu_x != 0` | 避免整帧左边界 |
| `cur_ctu_y != 0` | 避免整帧上边界 |

如果实际仿真中没有上述坐标，可选择任意满足 A/B availability 非零的 blk16 AMVP case。

## 4. 需要重点记录的信号

| 类别 | 信号 |
|---|---|
| Trigger | `amvp_cand_cu_start`, `amvp_blk_sz`, `reg_avc_mode`, `reg_i_slice` |
| Coordinate | `cur_cu_x`, `cur_cu_y`, `cur_ctu_x`, `cur_ctu_y` |
| Command | `amvp_cmd_out` |
| Neighbor | `amvp_neib_a`, `amvp_neib_b`, `amvp_col_c`, `amvp_col_c_avail`, `reflist_info` |
| Candidate mask | `cand_a`, `cand_b`, `cand_c` |
| FSM / Scale | `fsm_cand_cs`, `fsm_cand_ns`, `scale_start` |
| Selection | `cand0_sel_onehot`, `cand1_sel_onehot` |
| Output | `amvp_cand_mv`, `amvp_cand_rdy`, `amvp_cand_blk_done` |

## 5. 有效性判定

| 编号 | 判定标准 |
|---|---|
| 1 | AMVP candidate generation 被启动 |
| 2 | 当前 block size 为 blk16 |
| 3 | `reg_avc_mode == 0` |
| 4 | 当前不是 I slice |
| 5 | A-side 与 B-side availability 均非零 |
| 6 | `scale_start == 0` |
| 7 | candidate generation 正常完成 |
| 8 | `cand_mv[0]` 和 `cand_mv[1]` 至少一个为有效 AMVP candidate |
| 9 | 不依赖边界 fallback、AVC median、scaling 或强制 zero-only path |

## 6. 暂不要求

| 不要求项 | 原因 |
|---|---|
| blk8 行为 | G01 单独覆盖 |
| MV scaling | G06 单独覆盖 |
| AVC median predictor | G05 单独覆盖 |
| Merge blk16 | 不属于本 case |
| AMVP blk32 | 第一版 decoder scope 暂不恢复 |
