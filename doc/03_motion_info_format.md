# 03 Motion Info Format

## 1. Spatial Neighbor Info

| 字段 | 位宽 | 来源 | 说明 |
|---|---:|---|---|
| mvx | 16 | neib_a/neib_b[15:0] | X 方向 MV |
| mvy | 16 | neib_a/neib_b[31:16] | Y 方向 MV |
| ref_idx | 2 | neib_a/neib_b[33:32] | 参考帧索引 |
| valid | 1 | availability 逻辑 | Decoder 侧建议显式维护，原 34-bit 数据内不含 valid |

## 2. Colocated Neighbor Info

| 字段 | 位宽 | 来源 | 说明 |
|---|---:|---|---|
| mvx | 16 | col_c[15:0] | colocated MVX |
| mvy | 16 | col_c[31:16] | colocated MVY |
| pocdiff | 8 | col_c[39:32] | POC difference |
| intra | 1 | col_c[40] | colocated block 是否 intra |
| long | 1 | col_c[41] | long-term reference flag |
| valid | 1 | col_c_avail | C0/C1 是否可用 |

## 3. RefList Info

| 字段 | 位宽 | 来源 | 说明 |
|---|---:|---|---|
| poc | 32 | reflist_info[31:0] | reference picture POC |
| long | 1 | reflist_info[32] | long-term reference flag |

## 4. Candidate Info

| 字段 | 位宽 | 来源 | 说明 |
|---|---:|---|---|
| mvx | 16 | cand_mv[15:0] | candidate MVX |
| mvy | 16 | cand_mv[31:16] | candidate MVY |
| ref_idx | 2 | cand_mv[33:32] | candidate ref_idx |
| pocdiff | 8 | cand_mv[41:34] | candidate POC difference |
| long | 1 | cand_mv[42] | candidate long-term flag |

## 5. Final Decoder Motion Info

| 字段 | 位宽 | 来源 | 说明 |
|---|---:|---|---|
| mvx | 16 | selected_mvp + parsed_mvd_x | 最终送 MC 的 MVX |
| mvy | 16 | selected_mvp + parsed_mvd_y | 最终送 MC 的 MVY |
| ref_idx | 2 | parser 或 selected merge candidate | 最终参考帧索引 |
| long | 1 | ref list / candidate | long-term flag |
| valid | 1 | decoder 控制 | 当前块是否产生有效 inter motion info |

注意：原 encoder RTL 中 neib_a/neib_b 的 34-bit spatial neighbor 数据本身不包含 valid bit。
valid/availability 由 cu_cmd_out、边界判断、reg_avc_mode 特判以及 get_neib 内部逻辑共同决定。
Decoder 侧为了避免 motion data 与 availability 混淆，建议显式拆分 valid 与 motion payload。