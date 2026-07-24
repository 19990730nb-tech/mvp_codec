# G08 Merge blk8 Basic Condition

## 1. Case Definition

| 项目 | 内容 |
|---|---|
| Case ID | G08 |
| Mode | Merge |
| Block Size | blk8 |
| AVC mode | 0 |
| 是否需要 scaling | No，优先选择 `scale_start=0` |
| 是否边界 case | No |
| 主要验证点 | 普通非边界、A/B 可用时，Merge blk8 candidate 顺序与基础输出 |

## 2. 必须满足的触发条件

| 条件 | 判定方式 |
|---|---|
| Merge path 有效 | `mrg_cand_cu_start == 1` 或 Merge candidate FSM 从 IDLE 跳转 |
| blk8 | `mrg_blk_sz[0] == 1` |
| 非 AVC mode | `reg_avc_mode == 0` |
| 非 I slice | `reg_i_slice == 0`，且 Merge Top 未被 `g_reg_i_slice` 抑制 |
| 非边界 | `cur_cu_a_avail != 0` 且 `cur_cu_b_avail != 0` |
| A/B neighbor 可用 | `mrg_cmd_out` 中 A/B availability 不全为 0，且 `mrg_neib_a/mrg_neib_b` 有有效 payload |
| 不走 scaling | 优先 `scale_start == 0` |
| candidate 正常完成 | `mrg_cand_rdy != 0` 且 `mrg_cand_blk_done == 1` |

## 3. 建议优先选择的坐标

| 坐标 | 说明 |
|---|---|
| `cur_cu_x = 2` | 避免左边界 |
| `cur_cu_y = 2` | 避免上边界 |
| `cur_ctu_x != 0` | 避免整帧左边界 |
| `cur_ctu_y != 0` | 避免整帧上边界 |

如果实际仿真中没有刚好 `(2,2)`，可选择任意满足 A/B availability 非零的 blk8 Merge case。

## 4. 需要重点记录的信号

| 类别 | 信号 |
|---|---|
| Trigger | `mrg_cand_cu_start`, `mrg_blk_sz`, `reg_avc_mode`, `reg_i_slice` |
| Coordinate | `cur_cu_x`, `cur_cu_y`, `cur_ctu_x`, `cur_ctu_y` |
| Command | `mrg_cmd_out` |
| Neighbor | `mrg_neib_a`, `mrg_neib_b`, `mrg_col_c`, `mrg_col_c_avail`, `reflist_info` |
| Candidate mask | `cand_a`, `cand_b`, `cand_c` |
| FSM / Scale | `fsm_cand_cs`, `fsm_cand_ns`, `scale_start` |
| Selection | `cand0_sel_onehot`, `cand1_sel_onehot` |
| Output | `mrg_cand_mv`, `mrg_cand_rdy`, `mrg_cand_blk_done` |

## 5. 有效性判定

| 编号 | 判定标准 |
|---|---|
| 1 | Merge candidate generation 被启动 |
| 2 | 当前 block size 为 blk8 |
| 3 | `reg_avc_mode == 0` |
| 4 | 当前不是 I slice，且 Merge path 未被抑制 |
| 5 | A-side 与 B-side availability 均非零 |
| 6 | candidate generation 正常完成 |
| 7 | 至少一个 Merge candidate 有效 |
| 8 | 该 case 不依赖边界 fallback、AVC mode、强制 temporal-only 或 zero-only path |

## 6. 暂不要求

| 不要求项 | 原因 |
|---|---|
| Merge blk16/blk32 | G09/G10 或后续 case 单独覆盖 |
| Merge 去重 corner case | G11 单独覆盖 |
| temporal / zero candidate 补足 | G12 单独覆盖 |
| AMVP path | 不属于本 case |
