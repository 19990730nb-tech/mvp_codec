# 05 Wave Signal Path

## 1. 顶层基本输入

| 逻辑信号 | 建议波形路径 | 说明 |
|---|---|---|
| reg_avc_mode | <DUT>.reg_avc_mode | AVC mode 标志 |
| reg_i_slice | <DUT>.reg_i_slice | I slice 标志 |
| reg_tmp_mvp_flag | <DUT>.reg_tmp_mvp_flag | temporal MVP enable |
| reg_cur_poc | <DUT>.reg_cur_poc | 当前 POC |
| reg_col_ref_idx | <DUT>.reg_col_ref_idx | colocated ref index |
| cur_ctu_start | <DUT>.cur_ctu_start | 当前 CTU start |
| cur_cu_start | <DUT>.cur_cu_start | 当前 CU start |
| cur_cu_x | <DUT>.cur_cu_x | 当前 CU x，8x8 slot |
| cur_cu_y | <DUT>.cur_cu_y | 当前 CU y，8x8 slot |
| cur_ctu_x | <DUT>.cur_ctu_x | 当前 CTU x |
| cur_ctu_y | <DUT>.cur_ctu_y | 当前 CTU y |
| cur_cu_a_avail | <DUT>.cur_cu_a_avail | A-side availability 输入 |
| cur_cu_b_avail | <DUT>.cur_cu_b_avail | B-side availability 输入 |

## 2. AMVP Path

| 逻辑信号 | 建议波形路径 | 说明 |
|---|---|---|
| amvp_blk_sz | <DUT>.amvp_blk_sz | AMVP block size enable |
| amvp_cmd_out | <DUT>.amvp_cmd_out | AMVP cu command |
| amvp_neib_cu_start | <DUT>.amvp_neib_cu_start | AMVP neighbor start |
| neib_done_amvp | <DUT>.neib_done_amvp | AMVP neighbor done |
| amvp_neib_a | <DUT>.amvp_neib_a | AMVP A0/A1 |
| amvp_neib_b | <DUT>.amvp_neib_b | AMVP B0/B1/B2 |
| amvp_col_c | <DUT>.amvp_col_c | AMVP C0/C1 |
| amvp_col_c_avail | <DUT>.amvp_col_c_avail | AMVP C0/C1 availability |
| reflist_info | <DUT>.reflist_info | reference POC / long-term |
| amvp_cur_ref_idx | <DUT>.U_VE_AMVP_TOP.cur_ref_idx | AMVP current ref_idx |
| amvp_cand_cu_start | <DUT>.U_VE_AMVP_TOP.cand_cu_start | AMVP candidate start |
| amvp_cand_mv | <DUT>.U_VE_AMVP_TOP.cand_mv | AMVP candidate output |
| amvp_cand_rdy | <DUT>.U_VE_AMVP_TOP.cand_rdy | AMVP candidate valid |
| amvp_cand_blk_done | <DUT>.U_VE_AMVP_TOP.cand_blk_done | AMVP candidate done |
| amvp_dbg_fsm_cand_cs | <DUT>.U_VE_AMVP_TOP.dbg_fsm_cand_cs | AMVP candidate FSM |

## 3. AMVP Candidate Internal

| 逻辑信号 | 建议波形路径 | 说明 |
|---|---|---|
| cand_a | <DUT>.U_VE_AMVP_TOP.U_VC_AMVP_CAND_GEN.cand_a | A-side candidate mask |
| cand_b | <DUT>.U_VE_AMVP_TOP.U_VC_AMVP_CAND_GEN.cand_b | B-side candidate mask |
| cand_c | <DUT>.U_VE_AMVP_TOP.U_VC_AMVP_CAND_GEN.cand_c | C-side candidate mask |
| cand0_sel_onehot | <DUT>.U_VE_AMVP_TOP.U_VC_AMVP_CAND_GEN.cand0_sel_onehot | cand0 select |
| cand1_sel_onehot | <DUT>.U_VE_AMVP_TOP.U_VC_AMVP_CAND_GEN.cand1_sel_onehot | cand1 select |
| fsm_cand_cs | <DUT>.U_VE_AMVP_TOP.U_VC_AMVP_CAND_GEN.fsm_cand_cs | candidate FSM current state |
| fsm_cand_ns | <DUT>.U_VE_AMVP_TOP.U_VC_AMVP_CAND_GEN.fsm_cand_ns | candidate FSM next state |
| scale_start | <DUT>.U_VE_AMVP_TOP.U_VC_AMVP_CAND_GEN.scale_start | scaling start |
| scale_done | <DUT>.U_VE_AMVP_TOP.U_VC_AMVP_CAND_GEN.scale_done | scaling done |
| scale_mvx | <DUT>.U_VE_AMVP_TOP.U_VC_AMVP_CAND_GEN.scale_mvx | scaled MVX |
| scale_mvy | <DUT>.U_VE_AMVP_TOP.U_VC_AMVP_CAND_GEN.scale_mvy | scaled MVY |
| avc_mvpxy | <DUT>.U_VE_AMVP_TOP.U_VC_AMVP_CAND_GEN.avc_mvpxy | AVC median predictor |

## 4. Merge Path

| 逻辑信号 | 建议波形路径 | 说明 |
|---|---|---|
| mrg_blk_sz | <DUT>.mrg_blk_sz | Merge block size enable |
| mrg_cmd_out | <DUT>.mrg_cmd_out | Merge cu command |
| mrg_neib_cu_start | <DUT>.mrg_neib_cu_start | Merge neighbor start |
| neib_done_mrg | <DUT>.neib_done_mrg | Merge neighbor done |
| mrg_neib_a | <DUT>.mrg_neib_a | Merge A0/A1 |
| mrg_neib_b | <DUT>.mrg_neib_b | Merge B0/B1/B2 |
| mrg_col_c | <DUT>.mrg_col_c | Merge C0/C1 |
| mrg_col_c_avail | <DUT>.mrg_col_c_avail | Merge C0/C1 availability |
| mrg_cur_ref_idx | <DUT>.U_VE_MRG_TOP.cur_ref_idx | Merge current ref_idx |
| mrg_cand_cu_start | <DUT>.U_VE_MRG_TOP.cand_cu_start | Merge candidate start |
| mrg_cand_mv | <DUT>.U_VE_MRG_TOP.cand_mv | Merge candidate output |
| mrg_cand_rdy | <DUT>.U_VE_MRG_TOP.cand_rdy | Merge candidate valid |
| mrg_cand_blk_done | <DUT>.U_VE_MRG_TOP.cand_blk_done | Merge candidate done |
| mrg_dbg_fsm_cand_cs | <DUT>.U_VE_MRG_TOP.dbg_fsm_cand_cs | Merge candidate FSM |

## 5. Merge Candidate Internal

| 逻辑信号 | 建议波形路径 | 说明 |
|---|---|---|
| cand_a | <DUT>.U_VE_MRG_TOP.U_VC_MRG_CAND_GEN.cand_a | A-side candidate mask |
| cand_b | <DUT>.U_VE_MRG_TOP.U_VC_MRG_CAND_GEN.cand_b | B-side candidate mask |
| cand_c | <DUT>.U_VE_MRG_TOP.U_VC_MRG_CAND_GEN.cand_c | C-side candidate mask |
| cand0_sel_onehot | <DUT>.U_VE_MRG_TOP.U_VC_MRG_CAND_GEN.cand0_sel_onehot | cand0 select |
| cand1_sel_onehot | <DUT>.U_VE_MRG_TOP.U_VC_MRG_CAND_GEN.cand1_sel_onehot | cand1 select |
| fsm_cand_cs | <DUT>.U_VE_MRG_TOP.U_VC_MRG_CAND_GEN.fsm_cand_cs | candidate FSM current state |
| fsm_cand_ns | <DUT>.U_VE_MRG_TOP.U_VC_MRG_CAND_GEN.fsm_cand_ns | candidate FSM next state |
| scale_start | <DUT>.U_VE_MRG_TOP.U_VC_MRG_CAND_GEN.scale_start | scaling start |
| scale_done | <DUT>.U_VE_MRG_TOP.U_VC_MRG_CAND_GEN.scale_done | scaling done |
| scale_mvx | <DUT>.U_VE_MRG_TOP.U_VC_MRG_CAND_GEN.scale_mvx | scaled MVX |
| scale_mvy | <DUT>.U_VE_MRG_TOP.U_VC_MRG_CAND_GEN.scale_mvy | scaled MVY |

## 6. Neighbor Internal Optional

| 逻辑信号 | 建议波形路径 | 说明 |
|---|---|---|
| irpu2neib_a_req | <DUT>.irpu2neib_a_req | A neighbor memory request |
| irpu2neib_a_addr | <DUT>.irpu2neib_a_addr | A neighbor memory address |
| irpu2neib_b_req | <DUT>.irpu2neib_b_req | B neighbor memory request |
| irpu2neib_b_addr | <DUT>.irpu2neib_b_addr | B neighbor memory address |
| irpu2col_req | <DUT>.irpu2col_req | colocated memory request |
| irpu2col_addr | <DUT>.irpu2col_addr | colocated memory address |
| irpu2ref_req | <DUT>.irpu2ref_req | reflist memory request |
| irpu2ref_addr | <DUT>.irpu2ref_addr | reflist memory address |

## 7. Neighbor Internal Debug Optional

| 逻辑信号 | 建议波形路径 | 说明 |
|---|---|---|
| neib_fsm_cs | <DUT>.U_VC_MVP_GET_NEIB.fsm_neib_cs | neighbor FSM current state |
| neib_fsm_ns | <DUT>.U_VC_MVP_GET_NEIB.fsm_neib_ns | neighbor FSM next state |
| cmdq_cu_start | <DUT>.U_VC_MVP_GET_NEIB.cmdq_cu_start | get_neib 实际启动信号 |
| cu_cmd_out | <DUT>.U_VC_MVP_GET_NEIB.cu_cmd_out | get_neib 实际使用的 command |
| neib_done_con | <DUT>.U_VC_MVP_GET_NEIB.neib_done_con | get_neib 内部 done 条件 |