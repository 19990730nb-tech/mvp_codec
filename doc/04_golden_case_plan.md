# 04 Golden Case Plan

## 1. Golden Case 目标

本文件定义第一版 decoder MVP 改造前需要从现有 encoder-side MVP RTL 中抓取的代表性 case。
这些 case 用于后续 reference model、candidate core、neighbor subsystem、AMVP decoder path 和 Merge decoder path 的行为对拍。

## 2. Case 清单

| Case ID | Mode | Block Size | 条件 | 主要验证点 | 是否必须 |
|---|---|---|---|---|---|
| G01 | AMVP | blk8 | 普通非边界，A/B 均可用 | 基础 AMVP cand0/cand1 生成 | 必须 |
| G02 | AMVP | blk16 | 普通非边界，A/B 均可用 | blk16 下 A/B neighbor 选择 | 必须 |
| G03 | AMVP | blk8 | A 不可用，B 可用 | A-side 不可用时 candidate fallback | 必须 |
| G04 | AMVP | blk8 | B 不可用，A 可用 | B-side 不可用时 candidate fallback | 必须 |
| G05 | AMVP | blk8/blk16 | AVC mode=1 | AVC median predictor path | 必须 |
| G06 | AMVP | blk8/blk16 | 需要 MV scaling | scale_start / scale_done / scaled MV | 必须 |
| G07 | AMVP | blk8/blk16 | 不需要 MV scaling | unscaled candidate path | 必须 |
| G08 | Merge | blk8 | 普通非边界 | Merge candidate 顺序 | 必须 |
| G09 | Merge | blk16 | 普通非边界 | blk16 Merge neighbor 选择 | 必须 |
| G10 | Merge | blk32 | 普通非边界 | Merge blk32 保留路径 | 必须 |
| G11 | Merge | blk8/blk16 | A1/B1 重复或部分重复 | Merge candidate 去重逻辑 | 建议 |
| G12 | Merge | blk8/blk16 | spatial candidate 不足 | temporal / zero candidate 补足 | 必须 |
| G13 | TMVP | blk8/blk16/blk32 | C0 可用 | colocated C0 candidate | 必须 |
| G14 | TMVP | blk8/blk16/blk32 | C0 不可用，C1 可用 | colocated C1 fallback | 必须 |
| G15 | Boundary | blk8 | 左边界或上边界 | A/B availability 边界裁剪 | 必须 |

## 3. 每个 Case 需要记录的信号

### 3.1 基本输入

| 信号 | 说明 |
|---|---|
| reg_avc_mode | 是否 AVC mode |
| reg_i_slice | 是否 I slice |
| reg_tmp_mvp_flag | 是否允许 temporal MVP |
| blk_sz | 当前 block size |
| cux / cuy | 当前 CU/PU 在 CTU 内 8x8 slot 坐标 |
| ctux / ctuy | 当前 CTU 坐标 |
| cu_cmd_out | 当前 CU command |
| ref_idx | 当前参考帧索引 |

### 3.2 Neighbor 输入/输出

| 信号 | 说明 |
|---|---|
| neib_a | A0/A1 neighbor payload |
| neib_b | B0/B1/B2 neighbor payload |
| col_c | C0/C1 colocated payload |
| col_c_avail | C0/C1 availability |
| reflist_info | reference POC / long-term info |
| neib_done | neighbor 准备完成 |

### 3.3 Candidate 中间信号

| 信号 | 说明 |
|---|---|
| cand_a | A-side candidate mask |
| cand_b | B-side candidate mask |
| cand_c | colocated candidate mask |
| cand0_sel_onehot | cand0 选择 |
| cand1_sel_onehot | cand1 选择 |
| scale_start | scaling 启动 |
| scale_done | scaling 完成 |
| scale_mvx / scale_mvy | scaling 输出 MV |

### 3.4 Candidate 输出

| 信号 | 说明 |
|---|---|
| cand_mv[0] | candidate 0 |
| cand_mv[1] | candidate 1 |
| cand_rdy | candidate 有效 |
| cand_blk_done | 当前 block candidate 生成完成 |

