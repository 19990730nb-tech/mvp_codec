# 06 Golden Case Record Template

## Case Basic Info

| 项目 | 内容 |
|---|---|
| Case ID |  |
| Mode | AMVP / Merge / TMVP / Boundary |
| Block Size | blk8 / blk16 / blk32 |
| AVC mode | 0 / 1 |
| 是否需要 scaling | Yes / No |
| 是否边界 case | Yes / No |
| 主要验证点 |  |

## 1. Trigger / Coordinate

| 信号 | 波形值 | 说明 |
|---|---|---|
| cur_cu_start |  | 当前 CU start |
| cur_cu_x |  | 8x8 slot x |
| cur_cu_y |  | 8x8 slot y |
| cur_ctu_x |  | CTU x |
| cur_ctu_y |  | CTU y |
| blk_sz |  | block size one-hot |
| reg_avc_mode |  | AVC mode |
| reg_tmp_mvp_flag |  | temporal MVP enable |
| ref_idx |  | 当前参考帧索引 |

## 2. Neighbor Result

| 信号 | 波形值 | 说明 |
|---|---|---|
| neib_done_amvp / neib_done_mrg |  | neighbor done |
| neib_a |  | A0/A1 payload |
| neib_b |  | B0/B1/B2 payload |
| col_c |  | C0/C1 payload |
| col_c_avail |  | C0/C1 availability |
| reflist_info |  | reference POC / long-term |

## 3. Candidate Mask

| 信号 | 波形值 | 说明 |
|---|---|---|
| cand_a |  | A-side candidate mask |
| cand_b |  | B-side candidate mask |
| cand_c |  | C-side candidate mask |

## 4. Candidate FSM / Scale

| 信号 | 波形值 | 说明 |
|---|---|---|
| fsm_cand_cs |  | candidate FSM current state |
| fsm_cand_ns |  | candidate FSM next state |
| scale_start |  | scaling start |
| scale_done |  | scaling done |
| scale_mvx |  | scaled MVX |
| scale_mvy |  | scaled MVY |

## 5. Candidate Selection

| 信号 | 波形值 | 说明 |
|---|---|---|
| cand0_sel_onehot |  | cand0 select |
| cand1_sel_onehot |  | cand1 select |
| cand_mv[0] |  | candidate 0 |
| cand_mv[1] |  | candidate 1 |
| cand_rdy |  | candidate valid |
| cand_blk_done |  | candidate done |

## 6. Decoder-side Expected Selection

| 项目 | 值 | 说明 |
|---|---|---|
| mvp_l0_flag |  | AMVP decoder 后续选择 cand0/cand1 |
| merge_idx |  | Merge decoder 后续选择 merge candidate |
| selected_mvp |  | decoder reference model 预期选择结果 |
| final_mv |  | AMVP: selected_mvp + mvd；Merge: selected candidate |
| parsed_mvd_x |  | AMVP bitstream 解析出的 MVD X |
| parsed_mvd_y |  | AMVP bitstream 解析出的 MVD Y |

## 7. 结论

| 项目 | 内容 |
|---|---|
| 当前 case 是否有效 | Yes / No |
| 该 case 覆盖了什么行为 |  |
| 是否可作为 golden reference | Yes / No |
| 备注 |  |