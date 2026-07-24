# G05 AMVP AVC Median Condition

## 1. Case Definition

| 项目 | 内容 |
|---|---|
| Case ID | G05 |
| Mode | AMVP / AVC mode |
| Block Size | blk8 或 blk16 |
| AVC mode | 1 |
| 是否需要 scaling | No，优先选择 `scale_start=0` |
| 是否边界 case | No，优先非边界 |
| 主要验证点 | AVC mode 下 median predictor path，包括 `avc_mvpxy` 与 MED candidate 选择 |

## 2. 必须满足的触发条件

| 条件 | 判定方式 |
|---|---|
| AMVP path 有效 | `amvp_cand_cu_start == 1` 或 AMVP candidate FSM 从 IDLE 跳转 |
| AVC mode | `reg_avc_mode == 1` |
| 非 I slice | `reg_i_slice == 0` |
| block size | `amvp_blk_sz[0] == 1` 或 `amvp_blk_sz[1] == 1` |
| median 输入可观察 | `amvp_neib_a/amvp_neib_b` 有可解释 payload，且 A/B availability 不全为 0 |
| AVC median 被使用 | `avc_mvpxy` 有效，且 `cand0_sel_onehot` 指向 MED path |
| candidate 正常完成 | `amvp_cand_rdy == 1` 且 `amvp_cand_blk_done == 1` |

## 3. 建议优先选择的坐标

| 坐标 | 说明 |
|---|---|
| `cur_cu_x != 0` | 避免左边界导致 A-side 输入缺失 |
| `cur_cu_y != 0` | 避免上边界导致 B-side 输入缺失 |
| CTU 内部位置 | 优先选择 A/B availability 都不为 0 的位置 |

## 4. 需要重点记录的信号

| 类别 | 信号 |
|---|---|
| Trigger | `amvp_cand_cu_start`, `amvp_blk_sz`, `reg_avc_mode`, `reg_i_slice` |
| Coordinate | `cur_cu_x`, `cur_cu_y`, `cur_ctu_x`, `cur_ctu_y` |
| Command | `amvp_cmd_out` |
| Neighbor | `amvp_neib_a`, `amvp_neib_b` |
| AVC median | `avc_mvpxy` |
| Candidate mask | `cand_a`, `cand_b`, `cand_c` |
| Selection | `cand0_sel_onehot`, `cand1_sel_onehot` |
| Output | `amvp_cand_mv`, `amvp_cand_rdy`, `amvp_cand_blk_done` |

## 5. 有效性判定

| 编号 | 判定标准 |
|---|---|
| 1 | AMVP candidate generation 被启动 |
| 2 | `reg_avc_mode == 1` |
| 3 | 当前不是 I slice |
| 4 | `avc_mvpxy` 被计算并可观察 |
| 5 | `cand0_sel_onehot` 指向 MED path |
| 6 | `cand_mv[0]` 的 MV payload 与 `avc_mvpxy` 对应 |
| 7 | candidate generation 正常完成 |
| 8 | 该 case 不作为 scaling、TMVP 或 Merge 行为依据 |

## 6. 暂不要求

| 不要求项 | 原因 |
|---|---|
| AMVP HEVC-like unscaled path | G01/G02 单独覆盖 |
| MV scaling | G06 单独覆盖 |
| Merge candidate | 不属于本 case |
| 边界下 AVC fallback | 后续单独扩展 |
