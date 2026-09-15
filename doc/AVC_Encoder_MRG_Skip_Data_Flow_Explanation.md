# AVC 编码侧数据流讲解：AMVP 生成预测值，MRG 复用为 P-Skip 评估通道

## 1. 核对结论

本文对应框图：[`AVC_Encoder_MRG_Skip_Data_Flow.svg`](./AVC_Encoder_MRG_Skip_Data_Flow.svg)。

核对基线为远程仓库 `main@db805bef3b2c8401b39e7213478b4971e886f160` 下的 `src_encoder_ref`。逐项核对 `ve_mvp_top.v`、`ve_amvp_top.v`、`ve_mrg_top.v`、`vc_mvp_ctrl.v`、`vc_mvp_get_neib.v` 和 `vc_mvp_cand_gen.v` 后，框图的模块关系、有效路径、FIFO 下标、数据方向和握手方向均与当前 RTL 一致，不需要修改框图。

需要特别注意：框图中的“MRG 当作 Skip 使用”不是指重新运行一遍普通 HEVC Merge 候选生成，而是指 **AMVP 先产生 AVC P-Skip MV，再借用 MRG 已有的候选缓存、MC 代价交互和 MRG2CCU 结果 FIFO**。

## 2. 一句话总览

在 `reg_avc_mode=1` 时，同一个 AVC inter CU 同时形成两类结果：

1. AMVP 使用空间邻居生成 AVC candidate0，与 FME 实际 MV 配对，形成普通 inter 结果并送往 CCU。
2. blk16 AMVP 结果写入的同一脉冲派生出 `avc_*` sideband；该 sideband 注入 MRG 的 blk16 通道，由 MC 计算代价后形成 P-Skip 结果，再通过 MRG2CCU FIFO 送往 CCU。

最终选择普通 inter 还是 P-Skip 不在 MVP 子系统内完成，而由下游 CCU 的编码模式决策完成。

## 3. 模式切换：AMVP 保持工作，普通 MRG 前端被关闭

顶层 `ve_mvp_top` 生成：

```verilog
g_reg_i_slice = reg_avc_mode | reg_i_slice;
```

`g_reg_i_slice` 只送给 `ve_mrg_top.reg_i_slice`。因此在 `reg_avc_mode=1` 时：

- MRG 内部 `vc_mvp_ctrl` 把当前模式视为 I-slice，不启动普通 Merge command queue 和普通 Merge candidate generator。
- AMVP 仍接收原始 `reg_i_slice`，继续处理实际 AVC inter CU。
- `vc_mvp_get_neib` 在 AVC 模式下选择 AMVP command queue 状态和 AMVP 命令，邻居读取由 AMVP 路径主导。
- MRG 的后半段仍然可用：AVC sideband 注入、候选 FIFO、MC 接口、代价返回处理和 MRG2CCU FIFO 都没有被关闭。

所以这里的结构可以概括为：

```text
普通 MRG 前端关闭
        │
AMVP ── avc_* sideband ──> MRG 后半段 ──> MC ──> MRG2CCU FIFO
```

## 4. 第一条数据流：AVC AMVP 普通 inter 结果

### 4.1 CU 命令进入 AMVP

AMVP command queue 的写入条件为：

```verilog
cur_cu_start[i] & ~reg_i_slice & !cur_cu_is_skip & !cur_cu_terminate
```

因此本数据流描述的是进入 AMVP 的 AVC inter transaction。`cur_cu_is_skip=1` 或 `cur_cu_terminate=1` 的命令不会按普通 AMVP transaction 入队。

CU 命令携带块尺寸、块坐标、A/B 邻居可用性、ZMV/Skip/Terminate 等上下文。`vc_mvp_ctrl` 调度 blk8、blk16 命令，并按参考帧次序触发邻居读取和候选生成。

### 4.2 读取并整理空间邻居

共享模块 `vc_mvp_get_neib` 读取并缓存：

- A 侧空间邻居；
- B 侧空间邻居；
- Col C 与 RefList 信息；
- 供 MVBS 计算使用的 blk8/blk16 邻居 MV 快照。

在 AVC 模式下，候选生成的核心输入是空间邻居 A1、B1 和 C，其中：

```text
A = A1
B = B1
C = B0（B0 可用时），否则取 B2；B0/B2 均不可用时按 0 参与可用性回退
```

### 4.3 `vc_mvp_cand_gen` 生成 AVC candidate0

AVC candidate0 对 X、Y 分量分别计算有符号中值：

```text
candidate0.x = median(A1.x, B1.x, C.x)
candidate0.y = median(A1.y, B1.y, C.y)
```

RTL 还包含可用性回退：

| 有效邻居情况 | candidate0 |
|---|---|
| 只有 A1 可用 | A1 |
| 只有 B1 可用 | B1 |
| 只有 C 可用 | C |
| A1、B1、C 均不可用 | Z0，即零向量 |
| 至少两个相关输入可用 | 分量级 median |

在 `reg_avc_mode=1` 时：

- candidate FSM 从 `CAND_IDLE` 直接走向 `CAND_DONE`，不进入时域缩放等待状态；
- `cand1_sel_onehot` 被清零，所以 AMVP candidate1 无效；
- candidate0 由 `UA / Z0 / MED` 分支得到。

这里的 candidate0 是 **预测 MV（MVP）**，还不是 FME 找到的实际 MV。

### 4.4 与 FME 实际 MV 配对并计算 MVD

FME 返回 FIFO 提供实际 MV 和 `fme_ref_idx`。`ve_amvp_top` 让同一块尺寸、同一参考帧的 FME MV 与 candidate0 配对。

AVC 模式下 AMVP 选择被明确固定为 candidate0：

```verilog
cand_sel = ~reg_avc_mode &
           (mvdcost_cand0_sum > mvdcost_cand1_sum);
```

由于 `reg_avc_mode=1`，所以 `cand_sel=0`。MVD 的计算方向是：

```text
MVD.x = FME_MV.x - candidate0.x
MVD.y = FME_MV.y - candidate0.y
```

若 CU 带有 ZMV 指示，参与配对的实际 MV 会先被置零，再计算相对 candidate0 的 MVD。

### 4.5 AMVP 结果送往 CCU

`ve_amvp_top` 将以下字段写入对应块尺寸的 AMVP2CCU FIFO：

- 实际 MV；
- MVD.x、MVD.y；
- `ref_idx`；
- `cand_sel=0`；
- long-term 标志与 POC difference；
- A/B 边界的 MVBS 信息。

接口方向为：

```text
AMVP -- irpu_amvp_rdy / irpu_amvp_rd --> CCU
AMVP <-- irpu_amvp_ack ---------------- CCU
```

FIFO 在 `irpu_amvp_rdy & irpu_amvp_ack` 时弹出。该结果是普通 AVC inter 模式的候选结果。

## 5. 第二条数据流：从 blk16 AMVP 结果派生 P-Skip 候选

### 5.1 sideband 的触发点

`ve_amvp_top` 使用 blk16 AMVP2CCU FIFO 的写入脉冲产生：

```verilog
avc_mvp_push = reg_avc_mode & amvp2ccu_push[1];
```

下标 `[1]` 对应 blk16。这里必须区分两个事件：

- `amvp2ccu_push[1]`：AMVP 正在把 blk16 结果写入 AMVP2CCU FIFO；
- `irpu_amvp_rdy[1] & irpu_amvp_ack[1]`：CCU 消费该 FIFO 结果。

`avc_mvp_push` 取自前者，因此 P-Skip 支路与 AMVP 结果写入同时启动，不需要等待 CCU 先接收普通 inter 结果。

### 5.2 P-Skip MV 的零向量覆盖规则

普通情况下，P-Skip 候选使用 AMVP candidate0：

```text
avc_mvpxy = candidate0_MVP
```

但 RTL 检查 top/left 边界及对应零 MV 邻居：

```verilog
avc_zero_motion[0] = is_pic_top16  |
                     (B-edge neighbor available && B-edge neighbor MV == 0);
avc_zero_motion[1] = is_pic_left16 |
                     (A-edge neighbor available && A-edge neighbor MV == 0);

avc_mvpxy = (|avc_zero_motion) ? 0 : candidate0_MVP;
```

只要任一零运动条件成立，最终 P-Skip MV 就覆盖为零；否则使用 candidate0 的空间预测结果。

### 5.3 sideband 字段

AMVP 向 MRG 发送：

| 信号 | 来源或含义 |
|---|---|
| `avc_mvp_push` | blk16 sideband 有效脉冲 |
| `avc_ref_idx` | `{1'b0, fme_ref_idx}` |
| `avc_is_long` | candidate0 的 long-term 标志 |
| `avc_pocdiff` | candidate0 的 POC difference |
| `avc_mvpxy` | 零向量覆盖后的 P-Skip MV |
| `avc_mvd_gt4` | `{B-edge flags, A-edge flags}`，由 P-Skip MV 与 blk16 邻居 MV 比较得到 |

`avc_mvd_gt4` 是 8 bit 并行元数据，不是第二个运动矢量候选。

## 6. 第三条数据流：MRG 后半段复用并请求 MC 计算

### 6.1 注入 blk16 的 FIFO[2] 与 FIFO[3]

在 `reg_avc_mode=1` 时，`ve_mrg_top` 对 `i=1` 的 blk16 通道执行：

```verilog
cand_push[2] = avc_mvp_push;
cand_push[3] = avc_mvp_push;
```

两个 depth-1 FIFO 同拍写入：

- FIFO[2]：保存 `avc_mvpxy`、`avc_ref_idx`、`avc_is_long`、`avc_pocdiff`，是送给 MC 的候选主体；
- FIFO[3]：低 8 bit 保存 `avc_mvd_gt4`，作为最终结果打包所需的并行元数据。

虽然 FIFO[3] 位于通常的“candidate1 槽位”，但 AVC 模式只把它当元数据缓存，不能解释成 MC 的第二候选。

### 6.2 候选请求与握手

`avc_mvp_push` 直接置起：

```text
mrg_cand_rdy[1][0]
```

随后 MRG 通过 blk16 MC 通道输出：

```text
mrg2mc_cand_rdy[1]
mrg2mc_cand_data[1]
```

`mrg2mc_cand_data[1]` 包含：

- valid；
- 当前块像素坐标 `pic_x/pic_y`；
- 水平/垂直尺寸编码均为 2，即 blk16；
- `ref_idx`；
- P-Skip MV。

候选在以下条件下被 MC 接收：

```text
mrg2mc_cand_rdy[1] && mc2mrg_cand_ack[1]
```

候选请求被接收后，`mrg_cand_rdy[1][0]` 清零；`mrg2mc_cand_done[1]` 由现有完成状态机给出。候选 FIFO 此时并不立即弹出，它还要等待 MC 返回对应代价。

### 6.3 MC 返回代价

MC 返回：

```text
mc2mrg_cost_rdy[1]
mc2mrg_cost_data[1]   // SATD + SSE
```

MRG 的 cost ack 恒为 1：

```verilog
mrg2mc_cost_ack = 3'b111;
```

因此 blk16 cost handshake 为：

```text
mc2mrg_cost_rdy[1] && mrg2mc_cost_ack[1]
```

在 AVC 模式下，该握手同时产生 `cand_pop[2]` 和 `cand_pop[3]`，确保候选主体与元数据同步释放。

## 7. 第四条数据流：MRG Skip 结果打包并送往 CCU

### 7.1 cost handshake 同时触发结果写入

AVC 模式下：

```text
cand_pop[2] = cand_pop[3] = blk16 MC cost handshake
mrg2ccu_push[1] = cand_pop[2]
```

所以 MC 代价返回的同一事件完成三件事：

1. 弹出 FIFO[2]；
2. 弹出 FIFO[3]；
3. 将 blk16 P-Skip 结果写入 MRG2CCU FIFO[1]。

### 7.2 `cand_sel` 的准确理解

AMVP 的 `cand_sel` 在 AVC 模式下由表达式直接强制为 0；MRG 的 `cand_sel` 则没有写成 `reg_avc_mode ? 0 : ...`，仍保留通用 cost/candidate 选择结构。

不过在预期 AVC 有效通路中：

- 普通 MRG candidate1 不启动；
- `mrg_cand_rdy[1][0]` 是直接置起的唯一 MC 候选；
- FIFO[3] 只是元数据；
- `cand_diff[1]` 在 slice 初始化后保持 0，因此 `cand_sel[1]` 解析为 0。

框图保留 `cand_sel ? sel_cand_1 : sel_cand_0` 的打包形式，是为了忠实反映 RTL 的通用打包代码，而不是表示 AVC 会向 MC 发送两个 Skip 候选。

### 7.3 MRG2CCU 结果内容与握手

MRG Skip 结果包括：

- P-Skip MV、ref_idx、long-term、POC difference；
- MC 返回的 SATD 和 SSE；
- `mrg_idx/cand_sel`；
- FIFO[3] 低 8 bit 的 `avc_mvd_gt4`；
- blk16 motion-level 数据 `md_mvl[1]`。

接口方向为：

```text
MRG -- irpu_mrg_rdy[1] / irpu_mrg_rd[1] --> CCU
MRG <-- irpu_mrg_ack[1] ------------------- CCU
```

CCU 由此同时获得普通 AMVP inter 结果和经过 MC 评估的 P-Skip 结果，再在 MVP 子系统之外完成编码模式选择。

## 8. 完整时序顺序

| 顺序 | 事件 | 关键条件/信号 | 结果 |
|---:|---|---|---|
| 1 | AVC inter CU 进入 AMVP | `reg_avc_mode=1`，非 skip、非 terminate | AMVP command queue 入队 |
| 2 | 邻居读取 | `neib_cu_start` | A/B/Col/Ref 数据准备 |
| 3 | AVC candidate0 生成 | `cand_cu_start` | A1/B1/C median 或可用性回退 |
| 4 | FME MV 配对 | 同块尺寸、同 `fme_ref_idx` | 得到实际 MV 与 `MVD=MV-MVP` |
| 5 | 普通 inter 结果写入 | `amvp2ccu_push[1]` | AMVP2CCU FIFO[1] 写入 |
| 6 | P-Skip sideband 同拍产生 | `avc_mvp_push=amvp2ccu_push[1]` | `avc_*` 送到 MRG |
| 7 | MRG 双 FIFO 写入 | `cand_push[2]=cand_push[3]=1` | 候选主体与元数据缓存 |
| 8 | MC 接收候选 | `mrg2mc_cand_rdy[1] & mc2mrg_cand_ack[1]` | P-Skip MV 进入 MC |
| 9 | MC 返回代价 | `mc2mrg_cost_rdy[1] & mrg2mc_cost_ack[1]` | SATD/SSE 有效 |
| 10 | 弹出并写结果 | `cand_pop[2]=cand_pop[3]=1` | MRG2CCU FIFO[1] 写入 |
| 11 | CCU 分别消费两路结果 | `irpu_amvp_ack[1]`、`irpu_mrg_ack[1]` | 下游完成模式决策 |

AMVP2CCU 与 MRG2CCU 是两条独立的结果通路，CCU 的反压也分别作用于各自 FIFO；不能把二者理解成同一握手链。

## 9. “MRG 当作 Skip 使用”的边界

准确含义：

- AMVP 负责 AVC 空间预测值与 P-Skip MV 的形成；
- MRG 复用候选 buffering、MC handshake、cost capture、结果打包和 CCU FIFO；
- 只有 blk16 lane 被 AVC sideband 激活；
- CCU 同时接收普通 inter 与 P-Skip 两类结果并作最终选择。

不应误解为：

- MRG 在 AVC 下重新生成普通 HEVC Merge candidate list；
- FIFO[3] 是第二个 AVC Skip 候选；
- `cur_cu_is_skip=1` 的已决策 CU 重新进入 AMVP；
- MRG 在本模块内决定普通 inter 与 P-Skip 的最终编码模式。

## 10. RTL 核对锚点

| 核对内容 | RTL 文件与关键位置 |
|---|---|
| `g_reg_i_slice` 与 AMVP→MRG sideband 连线 | `src_encoder_ref/ve_mvp_top.v` |
| AMVP MVD、`cand_sel=0`、P-Skip 零向量覆盖、`avc_*` 输出 | `src_encoder_ref/ve_amvp_top.v` |
| AVC median、可用性回退、candidate1 关闭 | `src_encoder_ref/vc_mvp_cand_gen.v` |
| AMVP command queue 的 skip/terminate 过滤 | `src_encoder_ref/vc_mvp_ctrl.v` |
| AVC 下 Neighbor 选择 AMVP 命令及 blk16 邻居缓存 | `src_encoder_ref/vc_mvp_get_neib.v` |
| FIFO[2]/[3] 注入、MC 握手、cost pop、MRG2CCU 打包 | `src_encoder_ref/ve_mrg_top.v` |

## 11. 建议抓取的最小波形链

若要在 Verdi 中验证一笔 blk16 AVC inter transaction，按以下顺序观察即可：

```text
reg_avc_mode
→ cand_cu_start / cand_blk_done / cand_rdy[0]
→ fme2amvp_cand_rdy / amvp2fme_cand_ack
→ amvp2ccu_push[1] / avc_mvp_push
→ avc_mvpxy / avc_ref_idx / avc_mvd_gt4
→ cand_push[2] / cand_push[3]
→ mrg2mc_cand_rdy[1] / mc2mrg_cand_ack[1]
→ mc2mrg_cost_rdy[1] / mrg2mc_cost_ack[1]
→ cand_pop[2] / cand_pop[3]
→ irpu_mrg_rdy[1] / irpu_mrg_rd[1] / irpu_mrg_ack[1]
```

这条链能直接验证：AMVP 结果是否触发 sideband、MRG 是否只使用 blk16 candidate0、MC cost 是否正确触发双 FIFO pop，以及 Skip 结果是否最终进入 MRG2CCU FIFO[1]。
