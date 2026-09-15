# `src_codec_dev` 解码逻辑与 `src_encoder_ref` 编码逻辑对照分析

## 阅读范围与结论边界

- `src_encoder_ref`：原始/参考编码侧。
- `src_codec_dev`：当前解码侧。

总的结论是：`src_codec_dev` 没有重写 AVC MVP 算法。它保留 neighbor manager、AMVP candidate priority、AVC median 和 candidate FSM；主要新增的是 CCU decoder transaction、pending/valid 控制、candidate context tag、`MVP + MVD` 重建和 decoder-to-MC 输出。

---

## 1. Module Mapping

| 编码侧 | 解码侧 | 变化类型 | RTL 结论 |
|---|---|---|---|
| `ve_mvp_top.v` / `ve_mvp_top` | `vc_mvp_top.v` / `vc_mvp_top` | 重命名、修改、新增 | 保留 Merge、AMVP、neighbor manager 总连接；增加 `codec_mode`、CCU transaction、decoder MC mux。见 `src_codec_dev/vc_mvp_top.v:8-124`、`:251-283`。 |
| `ve_amvp_top.v` / `ve_amvp_top` | `vc_amvp_top.v` / `vc_amvp_top` | 重命名、重大修改 | 保留 encoder AMVP/FME/CCU pipeline；新增 decoder transaction register、MVD FIFO、context matching、final MV、P8x8 顺序控制。见 `src_codec_dev/vc_amvp_top.v:51-257`、`:919-1005`。 |
| `vc_mvp_ctrl.v` | `vc_mvp_ctrl.v` | 修改、复用 | 保留 one-hot FSM、每个 block size 一个 command FIFO、逐 ref 遍历；新增 `decoder_mode` 的 size scheduling 和 ref cursor 更新。见 `src_codec_dev/vc_mvp_ctrl.v:38-60`、`:297-357`、`:482-508`。 |
| `vc_mvp_get_neib.v` | `vc_mvp_get_neib.v` | 基本复用、接口小改 | A/B/Colocated/RefList request、response metadata、within-CTU cache 基本相同；decoder 通过上层合成 command 和 MC-accept update 使用它。见 `src_codec_dev/vc_mvp_get_neib.v:231-258`、`:842-976`、`:1018-1076`。 |
| `vc_mvp_cand_gen.v` | `vc_mvp_cand_gen.v` | 基本复用 | AMVP/Merge priority、duplicate removal、temporal scaling、AVC median 和 FSM 保留。见 `src_codec_dev/vc_mvp_cand_gen.v:48-78`、`:214-305`、`:420-465`。 |
| `vc_mvp_cand_prior.v` | `vc_mvp_cand_prior.v` | 基本复用 | 仍由有效性、POC、long-term、scaling 生成 `cand_a/cand_b/cand_c`。见 `src_codec_dev/vc_mvp_cand_prior.v:79-168`。 |
| `vc_mvp_rd_mem.v` | `vc_mvp_rd_mem.v` | 基本复用 | 通用 `MEM_IDLE → MEM_GET → MEM_CHK_DQ`，用 metadata FIFO 匹配返回数据。见 `src_codec_dev/vc_mvp_rd_mem.v:87-104`、`:261-330`。 |
| `vc_mvp_scale.v` | `vc_mvp_scale.v` | 基本复用 | 保留 temporal MV scaling；decoder AVC 最终仍消费 candidate 0。 |
| `ve_mrg_top.v` | `ve_mrg_top.v` | 保留、decoder bypass | Merge pipeline 仍实例化，但 `decoder_mode` 固定为 `1'b0`；decoder 模式下公共 MC/cost 输出不走 Merge。见 `src_codec_dev/ve_mrg_top.v:697-736`、`src_codec_dev/vc_mvp_top.v:251-283`。 |
| `sht_mdl.v`、`ve_defines.v`、`ve_irpu_expg_bits.v`、`ve_reg_struct.v` | `src_codec_dev` 中没有对应文件 | 共享依赖未复制 | decoder RTL 仍实例化/引用这些符号；应由工程 file list/include path 提供，不能据此认定算法删除。 |

归类：共享算法是“复用”；`vc_mvp_ctrl/vc_amvp_top/vc_mvp_top` 是“修改”；decoder transaction、pending、context tag、final MV 和 MC mux 是“新增”；FME actual-MV、encoder cost decision、Merge-to-MC 是 decoder 下“旁路”；没有删除共享 candidate generation。

---

## 2. Overall Flow Comparison

### Encoder flow

```text
cur_cu_start / mode decision
 → ve_mvp_top
 → ve_amvp_top + ve_mrg_top
 → vc_mvp_ctrl：按 block size 排队、逐 active ref 遍历
 → vc_mvp_get_neib：A/B/Colocated/RefList
 → vc_mvp_cand_prior + vc_mvp_cand_gen：candidate 0/1
 → FME 提供 actual MV
 → actual MV 与 MVP 做差，计算 MVD/cost
 → cand_sel 选择 candidate 0/1
 → AMVP CCU FIFO / Merge MC interface
```

参考证据：`src_encoder_ref/ve_mvp_top.v:265-467` 同时连接 Merge/AMVP，`src_encoder_ref/ve_amvp_top.v:225-278` 处理 FME、candidate join、MVD/cost，`:343-355` 生成 AMVP-to-CCU push。

### Decoder flow

```text
CCU：valid + ref_idx + MVD + part_mode + sub_idx + skip
 → irpu2ccu_rdy 通过后，单笔 transaction register
 → 合成 P8/P16 AMVP command
 → vc_mvp_ctrl：只启用指定 block size，仍遍历 active refs
 → vc_mvp_get_neib：A/B/Colocated/RefList + 已重建 cache
 → vc_mvp_cand_gen：生成 AVC candidate 0
 → MVD FIFO 与带坐标/尺寸/ref_idx tag 的 candidate FIFO rendezvous
 → final MV = MVP + MVD
 → P8/P16 对应 MC lane
 → MC accept 后更新 neighbor cache
```

关键证据：

- `src_codec_dev/vc_amvp_top.v:318-321`：decoder `ready/accept`。
- `src_codec_dev/vc_amvp_top.v:352-355`：decoder 用 CCU MVD/ref_idx，encoder 才用 FME actual MV。
- `src_codec_dev/vc_amvp_top.v:422-450`：candidate/MVD context matching。
- `src_codec_dev/vc_amvp_top.v:462-469`：`MVP + MVD`。
- `src_codec_dev/vc_mvp_top.v:255-271`：decoder final MV 进入公共 MC interface。
- `src_codec_dev/vc_mvp_top.v:277-283`：MC accept 后更新 neighbor cache。

---

## 3. Module-by-Module Analysis

## 3.1 Top：`ve_mvp_top` → `vc_mvp_top`

### Encoder behavior:

`ve_mvp_top` 接收 CTU/CU、mode decision、FME、MC、CCU 和 memory 接口，直接连接 `ve_mrg_top`、`ve_amvp_top` 和 `vc_mvp_get_neib`。坐标由 `{ctu, cu, 3'd0}` 形成，Merge 和 AMVP 共用 neighbor manager。

证据：`src_encoder_ref/ve_mvp_top.v:249-259`、`:265-467`、`:437-515`。

### Decoder behavior:

`vc_mvp_top` 新增 decoder 输入：`codec_mode`、`ccu2irpu_valid`、`ccu2irpu_mvd`、`ccu2irpu_ref_idx`、`ccu2irpu_is_skip`、`ccu2irpu_part_mode`、`ccu2irpu_sub_idx`，以及 `irpu2ccu_rdy` 输出。

Merge 输出先进入 `enc_mrg2mc_*`，再按 `codec_mode` 选择：

```verilog
assign mrg2mc_cand_rdy  = codec_mode ? dec_mrg2mc_cand_rdy  : enc_mrg2mc_cand_rdy;
assign mrg2mc_cand_data = codec_mode ? dec_mrg2mc_cand_data : enc_mrg2mc_cand_data;
assign mrg2mc_cand_nb   = codec_mode ? 3'b000               : enc_mrg2mc_cand_nb;
assign mrg2mc_cost_ack  = codec_mode ? 3'b000               : enc_mrg2mc_cost_ack;
assign mrg2mc_cand_done = codec_mode ? dec_mrg2mc_cand_done : enc_mrg2mc_cand_done;
```

见 `src_codec_dev/vc_mvp_top.v:251-271`。

### Key difference:

编码侧 MC candidate 来自 Merge/AMVP 搜索结果；decoder MC candidate 来自 CCU syntax 重建的单笔 final MV。decoder 不用 Merge candidate/cost 作为运动信息来源。

### Reason:

编码端必须搜索候选；解码端已有 `ref_idx` 和 MVD，只需确定性地重建 MVP/final MV。

### RTL evidence:

```verilog
assign dec_mc_accept = dec_mv_valid &&
                       (dec_part_mode ? mc2mrg_cand_ack[0] : mc2mrg_cand_ack[1]);
```

见 `src_codec_dev/vc_mvp_top.v:251-253`；P8 使用 lane 0、`1x1`，P16 使用 lane 1、`2x2`，见 `:255-271`。

### `codec_mode` / `reg_avc_mode` 的实际路径

虽然顶层注释将二者描述为独立控制，但 decoder enable 实际是：

```verilog
assign avc_dec_en = reg_avc_mode & codec_mode;
```

见 `src_codec_dev/vc_amvp_top.v:405-406`。

- `codec_mode=0`：encoder path。
- `codec_mode=1 && reg_avc_mode=1`：当前真正实现的 AVC decoder path。
- `codec_mode=1 && reg_avc_mode=0`：顶层会选择 decoder MC mux、屏蔽 Merge MC ack/cost，但 `irpu2ccu_rdy=0`，decoder transaction 不会被接收。

后一个组合是 RTL 可直接确认的边界行为；是否由系统禁止该组合，`Uncertain — requires integration RTL/testbench confirmation.`

## 3.2 `vc_mvp_ctrl`

### Encoder behavior:

状态为：

```text
AMVP_IDLE → AMVP_WAIT_CU_START → AMVP_WAIT_NEIB_DONE
 → AMVP_CAND_BLK8 → AMVP_CAND_BLK16 → AMVP_CAND_BLK32
 → AMVP_BLK_DONE
```

每种 block size 有一个深度为 1 的 14-bit command FIFO，packet 为：

```text
[13] terminate, [12] skip, [11] zmv,
[10:9] A availability, [8:6] B availability,
[5:3] cu_y, [2:0] cu_x
```

参考侧 AMVP push/pop：

```verilog
push[i] = cur_cu_start[i] & ~reg_i_slice & !cur_cu_is_skip & !cur_cu_terminate;
pop[i]  = cand_blk_sz[i] & cand_blk_done ? ref_idx[i] == num_ref_m1 : 1'b0;
```

见 `src_encoder_ref/vc_mvp_ctrl.v:107-151`。参考 FSM 从 BLK8 开始，candidate done 后依次进入更大 block size；一个 size 完成后若还有 ref，回到 `WAIT_NEIB_DONE`，见 `src_encoder_ref/vc_mvp_ctrl.v:258-320`。

### Decoder behavior:

decoder 由 `vc_amvp_top` 合成 AMVP ctrl 输入：

```verilog
assign ctrl_cur_cu_start = avc_dec_en ?
                           (dec_accept ? (ccu2irpu_part_mode ? 3'b001 : 3'b010) : 3'b000) :
                           cur_cu_start;
assign ctrl_cur_cu_is_skip = avc_dec_en ? 1'b0 : cur_cu_is_skip;
```

见 `src_codec_dev/vc_amvp_top.v:334-340`。

- P8x8：只 push BLK8 lane `3'b001`。
- P16x16：只 push BLK16 lane `3'b010`。
- decoder 仍使用 `ref_idx[]` 对 active reference 逐个生成 candidate。

`decoder_mode` 使 `WAIT_NEIB_DONE` 只启动非空的指定 size；candidate done 后直接去 `BLK_DONE`，不会像 encoder 一样继续搜索其他 block size。见 `src_codec_dev/vc_mvp_ctrl.v:297-347`。

### Key difference:

encoder 是“外部 CU 事件 + 多 size + 多 ref”；decoder 是“CCU transaction 指定 size + 该 size 仍可能遍历 active refs”。

### Reason:

解码端不能再把 partition 当成待搜索模式；但共用 candidate generator 时，仍需按 `cur_ref_idx` 产生 reference-specific candidate slot。

### RTL evidence:

- command packet：`src_codec_dev/vc_mvp_ctrl.v:121-135`。
- decoder size scheduling：`:297-347`。
- ref_idx 启动和递增：`:448-474`。
- decoder ref cursor reset/推进：`:482-508`。

`blk_sz_smallest_only`、`chk_ref_equal`、`ref_idx_sel` 等旧寄存器/信号仍在文件中，但当前没有形成 decoder 主要路径；只能视作遗留控制，不应推断为 decoder 额外 mode decision。

## 3.3 `vc_mvp_get_neib` 与 `vc_mvp_rd_mem`

### Encoder behavior:

参考顶层让 neighbor manager 同时服务 AMVP/Merge。它根据 command queue、block size、CU 坐标和 availability，决定 A/B/Colocated/RefList 的读取数量；`vc_mvp_rd_mem` 通过 request metadata FIFO 将外部返回数据写到正确 staging slot。

读取启动证据：

```verilog
assign neib_b_cu_start = cmdq_cu_start & |b_avail_cnt;
assign neib_a_cu_start = cmdq_cu_start & |a_avail_cnt;
assign neib_c_cu_start = cmdq_cu_start & reg_tmp_mvp_flag;
assign ref_avail_cnt   = reg_num_ref_l0_act_m1 + 1;
```

见 `src_encoder_ref/vc_mvp_get_neib.v:388-413`；RefList 实例见 `src_codec_dev/vc_mvp_get_neib.v:944-976`。

### Decoder behavior:

decoder 没有给 neighbor manager 增加 `codec_mode`；它通过 AMVP command 复用同一套读取。变化在：

1. `ctrl_cur_cu_start/x/y` 将 CCU transaction 变成 AMVP command。
2. P8x8 根据 sub-block 位置补 A1/B1 availability，见 `src_codec_dev/vc_amvp_top.v:342-350`。
3. final MV 只有 MC 接受后才作为 neighbor update：

```verilog
assign neib_cur_cu_upd        = codec_mode ? dec_mc_accept : cur_cu_upd;
assign neib_cur_cu_upd_sz     = codec_mode ? (dec_part_mode ? 2'd1 : 2'd2) : cur_cu_upd_sz;
assign neib_cur_cu_upd_x      = codec_mode ? dec_cu_x : cur_cu_upd_x;
assign neib_cur_cu_upd_y      = codec_mode ? dec_cu_y : cur_cu_upd_y;
assign neib_cur_cu_upd_mvx    = codec_mode ? dec_final_mv[0] : cur_cu_upd_mvx;
assign neib_cur_cu_upd_mvy    = codec_mode ? dec_final_mv[1] : cur_cu_upd_mvy;
assign neib_cur_cu_upd_refidx = codec_mode ? dec_ref_idx : cur_cu_upd_refidx;
```

见 `src_codec_dev/vc_mvp_top.v:275-283`。

### Key difference:

编码侧 cache update 来源是 mode decision `cur_cu_upd`；decoder 来源是 `dec_mc_accept + dec_final_mv`。因此 P8x8 后续 sub-block 只能看到已经完成 MC 接收的前一块。

### Reason:

解码侧在 MC accept 前 final MV 仍可能等待 candidate/FIFO，不能过早污染 within-CTU neighbor history。

### RTL evidence:

- `vc_mvp_get_neib.v:258-259`：external staging 与 within-CTU cache 组合。
- `vc_mvp_get_neib.v:391-418`：读取数量、`neib_done_con`。
- `vc_mvp_get_neib.v:443-523`：response metadata 和逻辑 A/B。
- `vc_mvp_get_neib.v:723-737`：P8x8 右半区 A1 使用 `a_0_reg`。
- `vc_mvp_get_neib.v:749-837`：按坐标将 `b_0_reg/buf_reg` overlay 为 B0/B1/B2。
- `vc_mvp_get_neib.v:1018-1040`：8/16/32 block cache update。
- `vc_mvp_rd_mem.v:91-102`、`:263-309`：request/grant、metadata FIFO、memory FSM。

具体用途：A/B 提供 spatial MV/ref_idx；Colocated 提供 temporal MV/POC diff/intra/long；RefList 提供当前及邻居 ref_idx 对应的 POC/long-term 属性。`ccu2irpu_ref_idx` 不直接写入 RefList memory，它只参与 decoder transaction 和 candidate slot 选择。

## 3.4 `vc_mvp_cand_prior` 与 `vc_mvp_cand_gen`

### Encoder behavior:

`vc_mvp_cand_prior` 的 AMVP priority 为：

```text
cand_a：A0/A1 unscaled → scaled A0/A1
cand_b：B0/B1/B2 unscaled → scaled B0/B1/B2
cand_c：C0 unscaled/scaled → C1 unscaled/scaled
```

unscaled 依据 reference POC/long-term 类别；scaled 通过 `vc_mvp_scale`。见 `src_encoder_ref/vc_mvp_cand_prior.v:79-168`。

`vc_mvp_cand_gen` 的 AMVP candidate 0 可来自 UA/SA/UB/SB/UC/SC/MED/Z0，candidate 1 可来自 UB/SB/UC/SC/Z1；共享 scaler 时二者可能不同周期 ready。见 `src_encoder_ref/vc_mvp_cand_gen.v:266-445`、`:1112-1510`。

encoder 用 FME actual MV 与两个 MVP 分别做差并比较 cost：

```verilog
{mvdabs_cand0[0], mvd_cand0[0]} = mvdabs_mvd(mvx, sel_cand_0[15:0]);
{mvdabs_cand1[0], mvd_cand1[0]} = mvdabs_mvd(mvx, sel_cand_1[15:0]);
assign cand_sel = ~reg_avc_mode & (mvdcost_cand0_sum > mvdcost_cand1_sum);
```

见 `src_encoder_ref/ve_amvp_top.v:264-278`。

### Decoder behavior:

decoder 直接实例化同一 candidate generator，见 `src_codec_dev/vc_amvp_top.v:700-732`。AVC 分支仍构造 candidate 0，但最后将 candidate 1 清零：

```verilog
if(reg_avc_mode)
    cand1_sel_onehot = 0;
```

见 `src_codec_dev/vc_mvp_cand_gen.v:1234-1248`、`:1354-1356`。因此 decoder 不重新评估 candidate 0/1，最终使用 `sel_cand_0`。

### Key difference:

encoder 的 candidate 0/1 是 cost decision 的两个候选；decoder 的 AVC candidate 0 是确定性 MVP，candidate 1 不参与 decoder 决策。

### Reason:

解码端必须复现编码端写入语法所对应的预测路径，不能重新进行 encoder mode decision。

### RTL evidence:

- candidate 入 FIFO：`src_codec_dev/vc_amvp_top.v:408-420`。
- decoder 只等待 candidate slot 0（两 active refs 时还等待 ref1 的 slot 0）：`:383-392`。
- cost arithmetic 保留但 `cand_sel` 被 decoder gate：`:475-482`。
- AMVP-to-CCU push/handshake 和 `avc_mvp_push` 在 decoder 下禁用：`:560-570`。

## 3.5 AVC median MVP

### Encoder behavior:

参考 `vc_mvp_cand_gen` 的 `avc_median` 按 X/Y 分量从 A1、B 组、C 组选择 median。B 组由 B1 和 B0/B2 组成；缺失 source 时选择唯一可用 source，多个 source 时用 signed compare。见 `src_encoder_ref/vc_mvp_cand_gen.v:402-445`。

### Decoder behavior:

同一 median 逻辑形成 `MED` candidate：

```verilog
cand0_sel_onehot[MED] : cand_mv[0][33:0] = {2'd0, avc_mvpxy};
```

见 `src_codec_dev/vc_mvp_cand_gen.v:350-360`。

`vc_amvp_top` 另外对 AVC MVP 做边界/zero-neighbor override：

```verilog
assign avc_zero_motion[0] = s_is_pic_top16 |
                            (mvbs_b_avail[1][0] & mvbs_neib_b[1][0] == 0);
assign avc_zero_motion[1] = s_is_pic_left16 |
                            (mvbs_a_avail[1][0] & mvbs_neib_a[1][0] == 0);
assign avc_mvpxy = |avc_zero_motion ? 0 : sel_cand_0[0+:32];
```

见 `src_codec_dev/vc_amvp_top.v:576-579`。

### Key difference:

普通 decoder transaction 的 final MV 使用 `sel_cand_0` 的 MVP；P_Skip 使用 `avc_mvpxy`，因此经过 zero-motion override。

### Reason:

当前 RTL 明确规定 P_Skip 忽略输入 MVD，使用 AVC zero/median MVP；普通 P8/P16 才执行 `MVP + MVD`。

### RTL evidence:

```verilog
if(dec_result_fire) begin
    dec_mv_valid_q    <= 1;
    dec_final_mv_q[0] <= dec_is_skip_q ? avc_mvpxy[0] : dec_mv_x_sum[15:0];
    dec_final_mv_q[1] <= dec_is_skip_q ? avc_mvpxy[1] : dec_mv_y_sum[15:0];
end
```

见 `src_codec_dev/vc_amvp_top.v:983-989`。

## 3.6 AMVP top：candidate evaluation → decoder transaction join

### Encoder behavior:

encoder 有三类 FIFO：

1. 每个 block size/reference/candidate 一个 candidate FIFO。
2. 每个 block size 一个 FME actual-MV FIFO。
3. 每个 block size 一个 AMVP-to-CCU FIFO。

参考 candidate payload 为 46 bit：`[45:43] size`、`[42] long`、`[41:34] POC diff`、`[33:32] ref_idx`、`[31:0] MV`，见 `src_encoder_ref/ve_amvp_top.v:118-130`。

### Decoder behavior:

candidate payload 扩展为 52 bit，新增 command 坐标：

```text
[51:49] cu_y, [48:46] cu_x, [45:43] size,
[42] long, [41:34] POC diff, [33:32] ref_idx, [31:0] MV
```

见 `src_codec_dev/vc_amvp_top.v:408-420`、`:735-760`。

decoder context match 是：

```verilog
assign dec_context_match[dec_i] = dec_pending_q &&
    (dec_part_mode_q ? dec_i == 0 : dec_i == 1) &&
    mv_q[dec_i][33:32] == dec_ref_idx_q &&
    cand_q[dec_i][dec_ref_idx_q[0]*NUM_REF][51:49] == dec_cu_y_q &&
    cand_q[dec_i][dec_ref_idx_q[0]*NUM_REF][48:46] == dec_cu_x_q &&
    cand_q[dec_i][dec_ref_idx_q[0]*NUM_REF][45:43] ==
        (dec_i == 0 ? 3'b001 : 3'b010);
```

见 `src_codec_dev/vc_amvp_top.v:422-431`。这同时约束 ref_idx、CU 坐标、partition size，并使 P8 只能匹配 lane0/size0，P16 只能匹配 lane1/size1。

### Key difference:

encoder join 是“同 ref_idx 的 FME actual MV + candidate”；decoder join 是“同 ref_idx、坐标、size 的 CCU MVD + candidate 0”。

### Reason:

decoder 有外部 transaction 和 P8x8 sub-block 顺序，必须防止 stale candidate 或错误 size candidate 被消费。

## 3.7 pending、valid-ready 和 final MV

### Encoder behavior:

FME 用 `fme2amvp_cand_rdy`/`amvp2fme_cand_ack` 传 actual MV；`irpu_amvp_rdy` 表示 AMVP output FIFO 有数据，CCU 用 `irpu_amvp_ack` 消费。见 `src_encoder_ref/ve_amvp_top.v:225-232`、`:343-355`。

### Decoder behavior:

decoder 使用单笔 ready/valid：

```verilog
assign irpu2ccu_rdy = avc_dec_en && !dec_pending_q && !dec_mv_valid_q &&
                      dec_input_queues_empty && dec_order_ok &&
                      dec_ref_idx_ok && dec_partition_ok;
assign dec_accept = ccu2irpu_valid && irpu2ccu_rdy;
```

见 `src_codec_dev/vc_amvp_top.v:308-321`。接受后 `dec_transaction_reg` 保存 MVD/ref/skip/partition/sub_idx/坐标；`dec_pending_q` 保持到 MC accept。

```text
dec_accept → pending
 → candidate/MVD rendezvous
 → dec_result_fire
 → dec_mv_valid + dec_final_mv_q
 → MC ack / dec_mc_accept
 → 清 pending 和 valid
```

证据：`src_codec_dev/vc_amvp_top.v:919-1005`。

### MVD 与 MVP 组合

```verilog
assign dec_mv_x_sum = $signed({selected_mvp_x[15], selected_mvp_x}) +
                      $signed({dec_mvd_q[0][15], dec_mvd_q[0]});
assign dec_mv_y_sum = $signed({selected_mvp_y[15], selected_mvp_y}) +
                      $signed({dec_mvd_q[1][15], dec_mvd_q[1]});
```

见 `src_codec_dev/vc_amvp_top.v:462-469`。结果锁存时取 `[15:0]`，见 `:985-989`；没有看到 saturate/clip，只有 `:1024-1029` 的 simulation warning。因此 overflow 的系统处理为 `Uncertain — requires RTL/testbench/waveform confirmation.` 当前 RTL 可确认的是低 16 bit 被锁存。

### Key difference:

encoder 是 FME producer → AMVP CCU producer；decoder 是 CCU syntax producer → AMVP reconstruction → MC producer。decoder 没有多笔外部 command FIFO，只有一个 registered transaction；内部 size command FIFO 仍是深度 1。

## 3.8 Merge、FME、cost、mode decision 的处理

### Encoder behavior:

`ve_mrg_top` 生成 Merge candidates，经过 MC candidate/cost handshake 和自己的 controller/FSM；`ve_amvp_top` 也将 `avc_mvp_push` 等 AVC 信息送给 Merge 侧。

### Decoder behavior:

Merge 的 controller 在 decoder 目录中固定为非 decoder：

```verilog
.decoder_mode          (1'b0),
.reg_num_ref_l0_act_m1 (4'd0),
```

见 `src_codec_dev/ve_mrg_top.v:697-736`。顶层 decoder 下屏蔽 Merge 的 MC ack/cost，并把公共 MC 输出切换到 decoder mux，见 `src_codec_dev/vc_mvp_top.v:392-434`、`:251-271`。

- FME actual MV：`amvp2fme_cand_ack=0`、`irpu_amvp_dlat=0`；motion FIFO 数据改为 `{ccu_ref_idx, ccu_mvd}`，见 `src_codec_dev/vc_amvp_top.v:352-355`、`:395-401`。
- cost：算术仍保留，但 `cand_sel = ~codec_mode & ~reg_avc_mode & (...)`，decoder 不用 cost 选 candidate，见 `:475-482`。
- AMVP output：`amvp2ccu_push` 和 `irpu_amvp_hsk` 在 AVC decoder 下 gate 掉，`avc_mvp_push` 也要求 `~codec_mode`，见 `:560-570`。
- mode decision：`cur_cu_upd_*` 端口保留，decoder 下改由 `dec_mc_accept/dec_final_mv` 驱动 neighbor update，见 `vc_mvp_top.v:275-283`。

`irpu_mrg_rdy/irpu_mrg_rd` 仍由 Merge 模块直接暴露，未见与 `codec_mode` 同样的统一 gate。因此能确认的是 Merge 到公共 MC/cost 的路径被旁路；外部是否还需忽略 Merge CCU 输出，`Uncertain — requires integration RTL/testbench confirmation.`

---

## 4. P16x16 / P8x8 Decoder Flow

### 4.1 P16x16

```text
CCU：part_mode=0，sub_idx=0，ref_idx 合法
 → dec_order_ok/dec_partition_ok
 → dec_accept
 → ctrl_cur_cu_start=3'b010，坐标不偏移
 → BLK16 command FIFO
 → neighbor A/B/C/RefList
 → AVC candidate 0
 → MVD FIFO {ref_idx,MVD}
 → context match：size=3'b010、坐标/ref_idx 匹配
 → final MV=MVP+MVD
 → dec_mv_valid
 → MC lane1，size=2'd2/2'd2
 → mc2mrg_cand_ack[1] / dec_mc_accept
 → 更新 16x16 neighbor cache
```

证据：`src_codec_dev/vc_amvp_top.v:334-339`、`:425-430`、`:442`；MC 数据为 `src_codec_dev/vc_mvp_top.v:266-271`。

### 4.2 P8x8

```text
CCU：part_mode=1，sub_idx=0/1/2/3
 → dec_input_cu_x=cur_cu_x+sub_idx[0]
   dec_input_cu_y=cur_cu_y+sub_idx[1]
   picture x/y 对应加 8 pixel
 → sub_idx 必须按 expected_sub_idx 顺序
 → dec_accept
 → ctrl_cur_cu_start=3'b001
 → BLK8 command FIFO
 → 使用前一 sub-block MC-accepted 的 A1/B1 history
 → AVC candidate 0
 → final MV=MVP+MVD
 → MC lane0，size=1x1
 → mc2mrg_cand_ack[0] / dec_mc_accept
 → 更新 cache，expected_sub_idx++
```

证据：坐标 `src_codec_dev/vc_amvp_top.v:300-306`；顺序 `:308-313`；A1/B1 availability `:342-350`；P8 sequence `:972-1003`；MC `src_codec_dev/vc_mvp_top.v:255-264`。

### 4.3 两种 partition 对比

| 项目 | P16x16 | P8x8 |
|---|---|---|
| `part_mode` | 0 | 1 |
| `sub_idx` | 必须 0 | 0→1→2→3，且 base CU 不变 |
| ctrl lane | `3'b010` | `3'b001` |
| context size | `3'b010` | `3'b001` |
| MC lane | 1 | 0 |
| MC size | 2x2 | 1x1 |
| neighbor update | 一次 16x16 | 每个 sub-block MC accept 后一次 |
| skip | 允许 | `dec_partition_ok` 禁止 |

skip 限制：

```verilog
assign dec_partition_ok = !ccu2irpu_is_skip || !ccu2irpu_part_mode;
```

见 `src_codec_dev/vc_amvp_top.v:314-320`。

---

## 5. Key Design Changes

```text
encoder reference traversal → decoder explicit ref_idx 消费
encoder candidate evaluation → decoder direct candidate-0 consumption
encoder MVD generation → decoder receives MVD
encoder mode decision update → decoder MC-accepted update
多 block-size 搜索 → transaction 指定 P8 或 P16
FME/cost/AMVP-to-CCU → decoder 下 bypass
```

具体对应：

1. **Reference**：scheduler 仍按 active refs 生成 slot，但 `dec_ref_idx_q` 决定从哪一个 slot 匹配/消费，见 `src_codec_dev/vc_amvp_top.v:422-430`。
2. **Candidate**：AVC 下 `cand1_sel_onehot=0`，`cand_sel` 又被 decoder gate，见 `src_codec_dev/vc_mvp_cand_gen.v:1354-1356` 和 `vc_amvp_top.v:479-482`。
3. **MVD**：encoder 是 `actual MV - MVP`；decoder 在 `:961-971` 锁存 `ccu2irpu_mvd`。
4. **Final MV**：decoder 在 `:466-469` 做 signed `MVP+MVD`，在 `:985-989` 锁存。
5. **Neighbor**：encoder `cur_cu_upd_*` 直接更新；decoder 只在 `dec_mc_accept` 更新，见 `vc_mvp_top.v:275-283`。
6. **Partition**：decoder ctrl 只 push `3'b001` 或 `3'b010`，并由 `vc_mvp_ctrl` 只运行对应 size，见 `vc_amvp_top.v:334-339`、`vc_mvp_ctrl.v:297-347`。
7. **Handshake**：新增 `irpu2ccu_rdy`、`dec_pending_q`、`dec_mv_valid_q`、`dec_context_match`、P8x8 sequence registers，防止输入重叠、stale candidate 和错误 sub-block 配对。

---

## 6. 仅凭当前 RTL 不能完全确认的事项

### 6.1 外部 memory response 时序

`vc_mvp_rd_mem` 用 `mem2ip_rd_lat` 出 metadata FIFO，但外部 memory 是否严格按 request 顺序返回，以及 grant/response 是否允许同周期，需 testbench/waveform。

### 6.2 `NUM_REF > 2`

decoder 合法性检查为：

```verilog
ccu2irpu_ref_idx[3:2] == 2'b00 && ccu2irpu_ref_idx[1:0] < NUM_REF
```

但 candidate push/context 又使用 `cur_ref_idx[0]`、`dec_ref_idx_q[0]*NUM_REF` 等 1-bit/2-bit 结构，工程默认更像 `NUM_REF=1/2`。`Uncertain — requires parameterized compile and simulation confirmation.`

### 6.3 active ref count 校验

`dec_ref_idx_ok` 只检查 `< NUM_REF`，没有检查 `< reg_num_ref_l0_act_m1+1`；而 scheduler/neighbor 读取数量使用 `reg_num_ref_l0_act_m1+1`。因此外部送入“低于 compile-time 上限、但超出当前 active ref 数”的 ref_idx 时，RTL 可能先 accept、后续找不到 candidate。系统是否保证此协议，`Uncertain — requires protocol assertion/testbench confirmation.`

### 6.4 `codec_mode=1 && reg_avc_mode=0`

公共 MC mux 进入 decoder 选择，但 `avc_dec_en=0` 导致 `irpu2ccu_rdy=0`。当前目录没有完整 HEVC-like decoder path 的证据，需 integration RTL 确认外部不会使用该组合。

### 6.5 final MV overflow

17-bit sum 被截取为低 16 bit，未见 clip/saturate；需要确认后级是否有额外处理。

### 6.6 Merge CCU 输出

Merge MC/cost 路径明确 bypass，但 `irpu_mrg_rdy/irpu_mrg_rd` 未统一 gate；外部是否忽略它们需 integration-level confirmation。

---

## 7. Final Summary

当前 decoder 主链路为：

```text
CCU command
 → 单笔 decoder transaction register
 → 合成 P8/P16 AMVP command
 → vc_mvp_ctrl
 → vc_mvp_get_neib 获取 A/B/Colocated/RefList
 → 复用 vc_mvp_cand_prior + vc_mvp_cand_gen 生成 AVC candidate 0
 → explicit ref_idx + 坐标 + size 与 MVD rendezvous
 → MVP + MVD 得到 final MV
 → P8/P16 对应 MC lane
 → MC accept 后更新 within-CTU neighbor cache
```

最核心的结构转换是：

```text
encoder：reference/FME candidate evaluation
decoder：explicit syntax transaction + direct candidate-0 reconstruction
```

共享的 neighbor/candidate 算法仍然存在；decoder bypass 的主要是 FME actual-MV 输入、MVD 生成、cost/mode decision、candidate1 选择以及 Merge 到 MC 的 encoder 消费路径。
