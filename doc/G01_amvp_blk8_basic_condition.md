# G01 AMVP blk8 Basic Condition

## 1. Case Definition

| 项目 | 内容 |
|---|---|
| Case ID | G01 |
| Mode | AMVP |
| Block Size | blk8 |
| AVC mode | 0 |
| 是否需要 scaling | No，优先选择 scale_start=0 的 unscaled path；若 scale_start=1，则该片段归入 G06
| 是否边界 case | No |
| 主要验证点 | 普通非边界、A/B 均可用时，AMVP cand0/cand1 基础生成 |

## 2. 必须满足的触发条件

| 条件 | 判定方式 |
|---|---|
| AMVP path 有效 | `amvp_cand_cu_start == 1` 或 AMVP candidate FSM 从 IDLE 跳转 |
| blk8 | `amvp_blk_sz[0] == 1` |
| 非 AVC mode | `reg_avc_mode == 0` |
| 非 I slice | `reg_i_slice == 0` |
| temporal MVP 不作为主要验证点 | `reg_tmp_mvp_flag` 可为 0 或 1，但本 case 重点看 A/B spatial candidate |
| 非边界 | `cur_cu_a_avail != 0` 且 `cur_cu_b_avail != 0` |
| A/B neighbor 均可用 | `amvp_cmd_out` 中 A/B availability 不全为 0，且 `amvp_neib_a/amvp_neib_b` 有有效 payload |
| candidate 正常完成 | `amvp_cand_rdy == 1` 且 `amvp_cand_blk_done == 1` |

## 3. 建议优先选择的坐标

优先选择 CTU 内部非边界位置，例如：

| 坐标 | 说明 |
|---|---|
| `cur_cu_x = 2` | 避免左边界 |
| `cur_cu_y = 2` | 避免上边界 |
| `cur_ctu_x != 0` | 避免整帧左边界 |
| `cur_ctu_y != 0` | 避免整帧上边界 |

如果实际仿真中没有刚好 `(2,2)`，可选择任意满足 A/B availability 非零的 blk8 AMVP case。

## 4. 需要重点记录的信号

| 类别 | 信号 |
|---|---|
| Trigger | `amvp_cand_cu_start`, `amvp_blk_sz`, `reg_avc_mode`, `reg_i_slice` |
| Coordinate | `cur_cu_x`, `cur_cu_y`, `cur_ctu_x`, `cur_ctu_y` |
| Command | `amvp_cmd_out` |
| Neighbor | `amvp_neib_a`, `amvp_neib_b`, `amvp_col_c`, `amvp_col_c_avail`, `reflist_info` |
| Candidate mask | `cand_a`, `cand_b`, `cand_c` |
| Selection | `cand0_sel_onehot`, `cand1_sel_onehot` |
| Output | `amvp_cand_mv`, `amvp_cand_rdy`, `amvp_cand_blk_done` |

## 5. G01 有效性判定

一个波形片段可以作为 G01 golden reference，当且仅当：

| 编号 | 判定标准 |
|---|---|
| 1 | AMVP candidate generation 被启动 |
| 2 | 当前 block size 为 blk8 |
| 3 | `reg_avc_mode == 0` |
| 4 | 当前不是 I slice |
| 5 | A-side 与 B-side availability 均非零 |
| 6 | candidate generation 正常完成 |
| 7 | `cand_mv[0]` 和 `cand_mv[1]` 至少一个为有效 AMVP candidate |
| 8 | 该 case 不依赖边界 fallback、AVC median 或强制 zero-only path |

## 6. 暂不要求

G01 不要求覆盖：

| 不要求项 | 原因 |
|---|---|
| MV scaling | G06 单独覆盖 |
| AVC median predictor | G05 单独覆盖 |
| C0/C1 fallback | G13/G14 单独覆盖 |
| 边界裁剪 | G15 单独覆盖 |
| Merge candidate order | G08-G12 单独覆盖 |