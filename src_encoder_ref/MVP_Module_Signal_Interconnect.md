# MVP Encoder RTL Module Signal Interconnect

> 范围：`src_encoder_ref`，从 `ve_mvp_top` 开始，向下追踪所有当前 RTL 中实际例化的 MVP 子模块。
>
> 目标：厘清父子模块以及同级子模块经父层 `wire/reg` 中转后的输入/输出关系。本文只记录当前 RTL 可直接核对的连接，不用标准行为补全源码未体现的路径。

## 0. 分析基线与记号

### 0.1 当前 `main` 源码快照

| 文件 | blob SHA |
|---|---|
| `ve_mvp_top.v` | `1842d5f5e7b30c8c14f7aaa8ecd827bd6229d5ee` |
| `ve_amvp_top.v` | `ee1b4d20fe6278e6fde64cd6d5b39f4b7ec43aba` |
| `ve_mrg_top.v` | `3b8b96c954b93ed0d862910c2e3cade0e7a377f0` |
| `vc_mvp_get_neib.v` | `ccbaf519f28c2ac72c4fd8183ae4ac3868179468` |
| `vc_mvp_ctrl.v` | `f27c722ac51dfb6688ad80ac6b03f591aacf6b20` |
| `vc_mvp_cand_gen.v` | `0a097356135f8a66ec52cb4f7df06165fd2b6e22` |
| `vc_mvp_cand_prior.v` | `c9733b1c5e9fef4a651e1867ed0c9231d320bf4e` |
| `vc_mvp_scale.v` | `3c15b593b651e0d0d715fff2fe8a960f550e014a` |
| `vc_mvp_rd_mem.v` | `0a6a12304a2fbb1d4205c875b084d743ef581e29` |
| `sht_mdl.v` | `4bac4686df22ee5aadb22f0139e8a4516c045f12` |
| `ve_irpu_expg_bits.v` | `3bf6f8999b29a232e5deb3b4fcfa68ade9a64322` |

### 0.2 方向记号

- `A.out -> [wire] -> B.in`：A 是信号生产者，B 是消费者，中间由父模块 `wire` 中转。
- `[comb/reg]`：信号在父模块先经过组合赋值或局部寄存器，再送往子模块。
- `[TOP PORT]`：直接来自/去往 `ve_mvp_top` 顶层端口。
- `sht_mdl` 的基本方向固定为：`push/pop/d/clk/rstz -> FIFO`，`FIFO -> full_n/n_full_n/empty_n/n_empty_n/q`。

---

## 1. 模块层次

```text
ve_mvp_top
├─ U_VE_MRG_TOP        : ve_mrg_top
│  ├─ U_VC_MRG_CTRL    : vc_mvp_ctrl      (AMVP_OR_MRG=0)
│  │  └─ ccu_cmdq[]    : sht_mdl
│  ├─ U_VC_MRG_CAND_GEN: vc_mvp_cand_gen  (AMVP_OR_MRG=0)
│  │  ├─ U_VC_MVP_CAND_PRIOR : vc_mvp_cand_prior
│  │  └─ U_VC_SCALE_CAL      : vc_mvp_scale   (MVP_SCALE_EN=1 时生成)
│  ├─ U_CAND_OUT_FIFO[]: sht_mdl
│  └─ U_MRG2CCU_FIFO[] : sht_mdl
├─ U_VE_AMVP_TOP       : ve_amvp_top
│  ├─ U_VC_AMVP_CTRL   : vc_mvp_ctrl      (AMVP_OR_MRG=1)
│  │  └─ ccu_cmdq[]    : sht_mdl
│  ├─ U_VC_AMVP_CAND_GEN: vc_mvp_cand_gen (AMVP_OR_MRG=1)
│  │  ├─ U_VC_MVP_CAND_PRIOR : vc_mvp_cand_prior
│  │  └─ U_VC_SCALE_CAL      : vc_mvp_scale   (MVP_SCALE_EN=1 时生成)
│  ├─ U_CAND_OUT_FIFO[]: sht_mdl
│  ├─ U_FME_16_CAND_FIFO / U_FME_8_CAND_FIFO : sht_mdl
│  ├─ U_AMVP2CCU_FIFO[]: sht_mdl
│  └─ VE_IRPU_EXPG_MVD_CAND{0,1}_{X,Y}: ve_irpu_expg_bits
└─ U_VC_MVP_GET_NEIB   : vc_mvp_get_neib
   ├─ U_GET_NEIB_A      : vc_mvp_rd_mem (NEIB_DIR_TYPE=1)
   │  └─ mem_cmd_fifo   : sht_mdl
   ├─ U_GET_NEIB_B      : vc_mvp_rd_mem (NEIB_DIR_TYPE=0)
   │  └─ mem_cmd_fifo   : sht_mdl
   ├─ U_GET_NEIB_C      : vc_mvp_rd_mem (NEIB_DIR_TYPE=2)
   │  └─ mem_cmd_fifo   : sht_mdl
   └─ U_GET_REFLIST     : vc_mvp_rd_mem (NEIB_DIR_TYPE=3)
      └─ mem_cmd_fifo   : sht_mdl
```

源码锚点：`ve_mvp_top.v::U_VE_MRG_TOP/U_VE_AMVP_TOP/U_VC_MVP_GET_NEIB`；各下级实例见对应文件的 `// instantiation` 区域。

---

## 1A. 模块互连图

### 1A.1 `ve_mvp_top` 一级模块互连图

> 依据：`ve_mvp_top` 中 `U_VE_MRG_TOP`、`U_VE_AMVP_TOP`、`U_VC_MVP_GET_NEIB` 三个实例的端口连接；箭头方向均表示**信号生产者 -> 消费者**。中途通过 `wire`/`assign` 中转的，直接写在箭头标签内。

```mermaid
flowchart LR
    subgraph TOP["ve_mvp_top"]
        MRG["U_VE_MRG_TOP<br/>ve_mrg_top"]
        AMVP["U_VE_AMVP_TOP<br/>ve_amvp_top"]
        NEIB["U_VC_MVP_GET_NEIB<br/>vc_mvp_get_neib"]
    end

    CCU["TOP CU / CTU inputs"]
    MEM["Neighbor / Col / Ref memory"]
    FME["FME"]
    MC["MC"]
    AMVP_CCU["CCU side<br/>irpu_amvp signals"]
    MRG_CCU["CCU side<br/>irpu_mrg signals"]

    CCU -->|"cur_ctu_start<br/>cur_cu_start, x, y<br/>cur_cu_a_avail, cur_cu_b_avail<br/>cur_cu_is_skip, zmv, terminate"| MRG
    CCU -->|"cur_ctu_start<br/>cur_cu_start, x, y<br/>cur_cu_a_avail, cur_cu_b_avail<br/>cur_cu_is_skip, zmv, terminate"| AMVP
    CCU -->|"cur_ctu_start<br/>cur_ctu_x, cur_ctu_y<br/>comb: pic_x, pic_y<br/>cur_cu_upd signals"| NEIB

    AMVP -->|"wire: amvp_blk_sz<br/>wire: amvp_cmd_out<br/>wire: cmdq_empty_n 1<br/>wire: amvp_neib_cu_start<br/>wire: blk_sz_lat_amvp<br/>wire: n_blk_sz_amvp"| NEIB
    NEIB -->|"wire: neib_done_amvp<br/>wire: amvp_neib_a, amvp_neib_b<br/>wire: amvp_col_c, amvp_col_c_avail<br/>wire: reflist_info<br/>wire: blk32, blk16, blk8 neighbor cache"| AMVP

    MRG -->|"wire: mrg_blk_sz<br/>wire: mrg_cmd_out<br/>wire: cmdq_empty_n 0<br/>wire: mrg_neib_cu_start<br/>wire: blk_sz_lat_mrg<br/>wire: n_blk_sz_mrg"| NEIB
    NEIB -->|"wire: neib_done_mrg<br/>wire: mrg_neib_a, mrg_neib_b<br/>wire: mrg_col_c, mrg_col_c_avail<br/>wire: reflist_info<br/>wire: blk32, blk16, blk8 neighbor cache"| MRG

    AMVP -->|"wire: avc_mvp_push<br/>avc_ref_idx<br/>avc_is_long<br/>avc_pocdiff<br/>avc_mvpxy<br/>avc_mvd_gt4"| MRG

    FME -->|"fme2amvp_cand_rdy<br/>fme2amvp_cand_mv"| AMVP
    AMVP -->|"amvp2fme_cand_ack"| FME

    MRG -->|"mrg2mc_cand_rdy, nb, data<br/>mrg2mc_cost_ack"| MC
    MC -->|"mc2mrg_cand_ack<br/>mc2mrg_cost_rdy, cost_data"| MRG

    NEIB -->|"irpu2neib_a req, addr<br/>irpu2neib_b req, addr<br/>irpu2col req, addr<br/>irpu2ref req, addr"| MEM
    MEM -->|"neib_a return<br/>neib_b return<br/>col return<br/>ref return"| NEIB

    AMVP -->|"irpu_amvp_rdy, rd, dlat, mv_info"| AMVP_CCU
    AMVP_CCU -->|"irpu_amvp_ack"| AMVP

    MRG -->|"irpu_mrg_rdy, rd"| MRG_CCU
    MRG_CCU -->|"irpu_mrg_ack"| MRG
```

### 1A.2 `ve_amvp_top` 内部互连图

> 依据：`ve_amvp_top` 中 `U_VC_AMVP_CTRL`、`U_VC_AMVP_CAND_GEN`、`U_CAND_OUT_FIFO`、`U_FME_*_CAND_FIFO`、`U_AMVP2CCU_FIFO`、`VE_IRPU_EXPG_*` 的例化与端口连接。

```mermaid
flowchart LR
    subgraph AMVP_TOP["ve_amvp_top"]
        CTRL["U_VC_AMVP_CTRL<br/>vc_mvp_ctrl"]
        CAND["U_VC_AMVP_CAND_GEN<br/>vc_mvp_cand_gen"]
        CFIFO["U_CAND_OUT_FIFO array<br/>sht_mdl"]
        F16["U_FME_16_CAND_FIFO<br/>sht_mdl"]
        F8["U_FME_8_CAND_FIFO<br/>sht_mdl"]
        COST["VE_IRPU_EXPG_MVD blocks<br/>ve_irpu_expg_bits x 4"]
        AFIFO["U_AMVP2CCU_FIFO array<br/>sht_mdl"]
    end

    NEIB_IN["Neighbor inputs<br/>neib_done_con<br/>neib_a, neib_b<br/>col_c, col_c_avail<br/>reflist_info<br/>neighbor cache"]
    FME_IN["FME side<br/>fme2amvp_cand_rdy<br/>fme2amvp_cand_mv"]
    CCU_OUT["CCU side<br/>irpu_amvp_rdy, irpu_amvp_rd"]

    CTRL -->|"wire: cand_cu_start<br/>wire: cur_ref_idx<br/>wire: cu_blk_en and cu_cmd_out<br/>comb: cu_cmd_out_sel"| CAND
    CAND -->|"wire: cand_blk_done<br/>wire: cand_blk_idle"| CTRL

    NEIB_IN --> CAND
    FME_IN --> F16
    FME_IN --> F8

    CAND -->|"cand_mv, cand_rdy<br/>comb: cand_push, cand_d"| CFIFO
    CFIFO -->|"cand_q<br/>cand_empty_n"| CAND

    F16 -->|"mv_q 1<br/>mv_empty_n 1, mv_full_n 1"| CAND
    F8 -->|"mv_q 0<br/>mv_empty_n 0, mv_full_n 0"| CAND
    CAND -->|"cand_pop 1"| F16
    CAND -->|"cand_pop 0"| F8

    CAND -->|"comb: mvd_cand0 and mvd_cand1, X and Y"| COST
    COST -->|"mvd_cost0 and mvd_cost1, X and Y"| CAND

    CAND -->|"comb: irpu_amvp_wd<br/>amvp2ccu_push<br/>irpu_amvp_hsk"| AFIFO
    AFIFO -->|"irpu_amvp_rdy<br/>irpu_amvp_rd"| CCU_OUT
```

### 1A.3 `ve_mrg_top` 内部互连图

> 依据：`ve_mrg_top` 中 `U_VC_MRG_CTRL`、`U_VC_MRG_CAND_GEN`、`U_CAND_OUT_FIFO`、`U_MRG2CCU_FIFO` 的例化与端口连接。

```mermaid
flowchart LR
    subgraph MRG_TOP["ve_mrg_top"]
        CTRL["U_VC_MRG_CTRL<br/>vc_mvp_ctrl"]
        CAND["U_VC_MRG_CAND_GEN<br/>vc_mvp_cand_gen"]
        CFIFO["U_CAND_OUT_FIFO array<br/>sht_mdl x 6"]
        FLOW["ve_mrg_top local flow FSM<br/>comb and reg logic"]
        MFIFO["U_MRG2CCU_FIFO array<br/>sht_mdl x 3"]
    end

    NEIB_IN["Neighbor inputs<br/>neib_done_con<br/>neib_a, neib_b<br/>col_c, col_c_avail<br/>reflist_info<br/>neighbor cache"]
    MC["MC side<br/>mc2mrg and mrg2mc signals"]
    CCU_OUT["CCU side<br/>irpu_mrg_rdy, irpu_mrg_rd"]

    CTRL -->|"wire: cand_cu_start<br/>wire: cur_ref_idx<br/>wire: cu_blk_en and cu_cmd_out<br/>comb: cu_cmd_out_sel"| CAND
    CAND -->|"wire: cand_blk_done<br/>wire: cand_blk_idle"| CTRL

    NEIB_IN --> CAND
    CAND -->|"cand_mv, cand_rdy<br/>comb: cand_push, cand_d"| CFIFO
    CFIFO -->|"cand_q<br/>cand_empty_n"| FLOW
    FLOW -->|"cand_pop"| CFIFO

    FLOW -->|"mrg2mc_cand_rdy, nb, data<br/>mrg2mc_cost_ack"| MC
    MC -->|"mc2mrg_cand_ack<br/>mc2mrg_cost_rdy, cost_data"| FLOW

    FLOW -->|"irpu_mrg_wd<br/>mrg2ccu_push<br/>irpu_mrg_hsk"| MFIFO
    MFIFO -->|"irpu_mrg_rdy<br/>irpu_mrg_rd"| CCU_OUT
```

### 1A.4 `vc_mvp_get_neib` 内部互连图

> 依据：`vc_mvp_get_neib` 内 4 个 `vc_mvp_rd_mem` 实例与外部 memory 回读、以及本层对 `*_rd` 数据的缓存/选择逻辑。

```mermaid
flowchart LR
    subgraph NEIB_TOP["vc_mvp_get_neib"]
        A["U_GET_NEIB_A<br/>vc_mvp_rd_mem"]
        B["U_GET_NEIB_B<br/>vc_mvp_rd_mem"]
        C["U_GET_NEIB_C<br/>vc_mvp_rd_mem"]
        R["U_GET_REFLIST<br/>vc_mvp_rd_mem"]
        SEL["local reg and comb<br/>neighbor cache registers<br/>reflist_info<br/>get_neib functions"]
    end

    CMD["AMVP / Merge command inputs"]
    MEM["Neighbor / Col / Ref memory"]
    OUT_AMVP["AMVP side outputs"]
    OUT_MRG["Merge side outputs"]

    CMD --> A
    CMD --> B
    CMD --> C
    CMD --> R

    A -->|"ip2mem_req, ip2mem_addr<br/>cmdq2ip_info: neib_a_info<br/>rd_mem_idle: get_neib_a_idle"| SEL
    B -->|"ip2mem_req, ip2mem_addr<br/>cmdq2ip_info: neib_b_info<br/>rd_mem_idle: get_neib_b_idle"| SEL
    C -->|"ip2mem_req, ip2mem_addr<br/>cmdq2ip_info: col_c_info<br/>rd_mem_idle: get_neib_c_idle"| SEL
    R -->|"ip2mem_req, ip2mem_addr<br/>cmdq2ip_info: ref_info<br/>rd_mem_idle: get_ref_idle"| SEL

    A -->|"req, addr"| MEM
    B -->|"req, addr"| MEM
    C -->|"req, addr"| MEM
    R -->|"req, addr"| MEM

    MEM -->|"neib_a gnt, rd_lat, rd"| SEL
    MEM -->|"neib_b gnt, rd_lat, rd"| SEL
    MEM -->|"col gnt, rd_lat, rd"| SEL
    MEM -->|"ref gnt, rd_lat, rd"| SEL

    SEL -->|"neib_done_amvp<br/>amvp_neib_a, amvp_neib_b<br/>amvp_col_c, amvp_col_c_avail<br/>reflist_info<br/>neighbor cache"| OUT_AMVP
    SEL -->|"neib_done_mrg<br/>mrg_neib_a, mrg_neib_b<br/>mrg_col_c, mrg_col_c_avail<br/>reflist_info<br/>neighbor cache"| OUT_MRG
```

> 重要限制：图中 `mrg_cu_start -> vc_mvp_get_neib` 仅表示**端口连接存在**；当前 `vc_mvp_get_neib` 内部 `cmdq_cu_start` 实际写死为 `amvp_cu_start`，见下文 2.7。图不能据此解读为 Merge 能独立启动 Neighbor。

---

## 2. `ve_mvp_top`：三个一级子模块之间的信号关系

### 2.1 AMVP -> Neighbor

| Producer | 父层中转 | Consumer | 方向/作用 |
|---|---|---|---|
| `U_VE_AMVP_TOP.cu_blk_en` | `[wire] amvp_blk_sz[2:0]` | `U_VC_MVP_GET_NEIB.amvp_blk_sz` | AMVP -> Neighbor，当前 AMVP block size one-hot |
| `U_VE_AMVP_TOP.cu_cmd_out` | `[wire] amvp_cmd_out[2:0][13:0]` | `U_VC_MVP_GET_NEIB.amvp_cmd_out` | AMVP -> Neighbor，CU command |
| `U_VE_AMVP_TOP.cmdq_empty_n` | `[wire] cmdq_empty_n[1][2:0]` | `U_VC_MVP_GET_NEIB.cmdq_empty_n[1]` | AMVP -> Neighbor，AMVP command queue 状态 |
| `U_VE_AMVP_TOP.neib_cu_start` | `[wire] amvp_neib_cu_start` | `U_VC_MVP_GET_NEIB.amvp_cu_start` | AMVP -> Neighbor，邻居读取启动 |
| `U_VE_AMVP_TOP.blk_sz_lat` | `[wire] blk_sz_lat_amvp` | `U_VC_MVP_GET_NEIB.blk_sz_lat_amvp` | AMVP -> Neighbor，block-size 切换脉冲 |
| `U_VE_AMVP_TOP.n_blk_sz` | `[wire] n_blk_sz_amvp[2:0]` | `U_VC_MVP_GET_NEIB.n_blk_sz_amvp` | AMVP -> Neighbor，下一 block-size 状态 |

### 2.2 Neighbor -> AMVP

| Producer | 父层中转 | Consumer | 方向/作用 |
|---|---|---|---|
| `U_VC_MVP_GET_NEIB.neib_done_amvp` | `[wire] neib_done_amvp` | `U_VE_AMVP_TOP.neib_done_con` | Neighbor -> AMVP，邻居准备完成 |
| `amvp_neib_b` | `[wire] amvp_neib_b[2:0][33:0]` | `U_VE_AMVP_TOP.neib_b` | Neighbor -> AMVP，B0/B1/B2 运动信息 |
| `amvp_neib_a` | `[wire] amvp_neib_a[1:0][33:0]` | `U_VE_AMVP_TOP.neib_a` | Neighbor -> AMVP，A0/A1 运动信息 |
| `amvp_col_c` | `[wire] amvp_col_c[1:0][41:0]` | `U_VE_AMVP_TOP.col_c` | Neighbor -> AMVP，colocated C0/C1 |
| `amvp_col_c_avail` | `[wire] amvp_col_c_avail[1:0]` | `U_VE_AMVP_TOP.col_c_avail` | Neighbor -> AMVP，C0/C1 availability |
| `reflist_info` | `[wire] reflist_info[NUM_REF-1:0][32:0]` | `U_VE_AMVP_TOP.reflist_info` | Neighbor -> AMVP，RefList POC/long-term |
| `blk32_neib_b_r` / `blk16_neib_b_r` / `blk8_neib_b_r` | `[wire] 同名` | `U_VE_AMVP_TOP.blk*_neib_b_r` | Neighbor -> AMVP，MVBS 辅助邻居缓存 |
| `blk32_neib_a_r` / `blk16_neib_a_r` / `blk8_neib_a_r` | `[wire] 同名` | `U_VE_AMVP_TOP.blk*_neib_a_r` | Neighbor -> AMVP，MVBS 辅助邻居缓存 |

### 2.3 Merge -> Neighbor

| Producer | 父层中转 | Consumer | 方向/作用 |
|---|---|---|---|
| `U_VE_MRG_TOP.cu_blk_en` | `[wire] mrg_blk_sz[2:0]` | `U_VC_MVP_GET_NEIB.mrg_blk_sz` | Merge -> Neighbor，Merge block size |
| `U_VE_MRG_TOP.cu_cmd_out` | `[wire] mrg_cmd_out[2:0][13:0]` | `U_VC_MVP_GET_NEIB.mrg_cmd_out` | Merge -> Neighbor，Merge CU command |
| `U_VE_MRG_TOP.cmdq_empty_n` | `[wire] cmdq_empty_n[0][2:0]` | `U_VC_MVP_GET_NEIB.cmdq_empty_n[0]` | Merge -> Neighbor，Merge queue 状态 |
| `U_VE_MRG_TOP.neib_cu_start` | `[wire] mrg_neib_cu_start` | `U_VC_MVP_GET_NEIB.mrg_cu_start` | Merge -> Neighbor，端口有连接；**当前有效启动逻辑见 2.7** |
| `U_VE_MRG_TOP.blk_sz_lat` | `[wire] blk_sz_lat_mrg` | `U_VC_MVP_GET_NEIB.blk_sz_lat_mrg` | Merge -> Neighbor，block-size 切换脉冲 |
| `U_VE_MRG_TOP.n_blk_sz` | `[wire] n_blk_sz_mrg[2:0]` | `U_VC_MVP_GET_NEIB.n_blk_sz_mrg` | Merge -> Neighbor，下一 block-size 状态 |

### 2.4 Neighbor -> Merge

| Producer | 父层中转 | Consumer | 方向/作用 |
|---|---|---|---|
| `neib_done_mrg` | `[wire] neib_done_mrg` | `U_VE_MRG_TOP.neib_done_con` | Neighbor -> Merge，邻居准备完成 |
| `mrg_neib_b` | `[wire] mrg_neib_b[2:0][33:0]` | `U_VE_MRG_TOP.neib_b` | Neighbor -> Merge，B-side |
| `mrg_neib_a` | `[wire] mrg_neib_a[1:0][33:0]` | `U_VE_MRG_TOP.neib_a` | Neighbor -> Merge，A-side |
| `mrg_col_c` | `[wire] mrg_col_c[1:0][41:0]` | `U_VE_MRG_TOP.col_c` | Neighbor -> Merge，colocated |
| `mrg_col_c_avail` | `[wire] mrg_col_c_avail[1:0]` | `U_VE_MRG_TOP.col_c_avail` | Neighbor -> Merge，colocated availability |
| `reflist_info` | `[wire] 同 AMVP 共用` | `U_VE_MRG_TOP.reflist_info` | Neighbor -> Merge，RefList |
| `blk{32,16,8}_neib_{a,b}_r` | `[wire] 与 AMVP 共用` | `U_VE_MRG_TOP.blk*_neib_*_r` | Neighbor -> Merge，MVBS 辅助数据 |

### 2.5 AMVP -> Merge 的 AVC sideband

这些信号并不经过 Neighbor，而是由 `ve_mvp_top` 的同名内部 `wire` 直接把 AMVP 输出接到 Merge 输入。

| Producer | `[wire]` | Consumer |
|---|---|---|
| `U_VE_AMVP_TOP.avc_mvp_push` | `avc_mvp_push` | `U_VE_MRG_TOP.avc_mvp_push` |
| `U_VE_AMVP_TOP.avc_ref_idx` | `avc_ref_idx[1:0]` | `U_VE_MRG_TOP.avc_ref_idx` |
| `U_VE_AMVP_TOP.avc_is_long` | `avc_is_long` | `U_VE_MRG_TOP.avc_is_long` |
| `U_VE_AMVP_TOP.avc_pocdiff` | `avc_pocdiff[7:0]` | `U_VE_MRG_TOP.avc_pocdiff` |
| `U_VE_AMVP_TOP.avc_mvpxy` | `avc_mvpxy[1:0][15:0]` | `U_VE_MRG_TOP.avc_mvpxy` |
| `U_VE_AMVP_TOP.avc_mvd_gt4` | `avc_mvd_gt4[1:0][3:0]` | `U_VE_MRG_TOP.avc_mvd_gt4` |

### 2.6 顶层组合中转后再送子模块的信号

| 顶层来源 | 中间信号 | 去向 | 备注 |
|---|---|---|---|
| `reg_avc_mode`, `reg_i_slice` | `[wire/assign] g_reg_i_slice = reg_avc_mode \| reg_i_slice` | `U_VE_MRG_TOP.reg_i_slice` | Merge 接收的不是原始 `reg_i_slice` |
| `cur_ctu_x/cur_cu_x` | `[reg comb] pic_x` | `U_VE_MRG_TOP.pic_x`, `U_VC_MVP_GET_NEIB.pic_x` | 当前块像素 X 坐标 |
| `cur_ctu_y/cur_cu_y` | `[reg comb] pic_y` | `U_VE_MRG_TOP.pic_y`, `U_VC_MVP_GET_NEIB.pic_y` | 当前块像素 Y 坐标 |
| 图宽/当前坐标 | `[wire/assign] is_pic_right[1:0]` | `U_VE_AMVP_TOP.is_pic_right` | AVC AMVP B2 availability 相关 |
| 当前坐标 | `[wire/assign] is_pic_top16` | `U_VE_AMVP_TOP.is_pic_top16` | AVC/MVBS 辅助 |
| 当前坐标 | `[wire/assign] is_pic_left16` | `U_VE_AMVP_TOP.is_pic_left16` | AVC/MVBS 辅助 |

### 2.7 **必须注意：端口已连接不等于当前有效控制路径**

`vc_mvp_get_neib.v` 当前有以下直接赋值：

```verilog
assign cmdq_cu_start  = amvp_cu_start;
assign cu_cmd_out     = amvp_cmd_out[0];
assign g_cmdq_empty_n = cmdq_empty_n[reg_avc_mode];
```

因此：

1. `mrg_cu_start -> U_VC_MVP_GET_NEIB.mrg_cu_start` **物理上有端口连接**，但当前 `cmdq_cu_start` 的有效来源被写死为 `amvp_cu_start`。
2. 当前 Neighbor 主命令 `cu_cmd_out` 被写死取 `amvp_cmd_out[0]`。
3. `g_cmdq_empty_n` 才根据 `reg_avc_mode` 在 Merge/AMVP 两组 queue 状态之间选择。

结论只描述当前 RTL：`mrg_cu_start` 不能按“已连接”直接等价为“能够启动 Neighbor”。后续若改 Merge/Decoder 路径，需要回看这里。

---

## 3. `ve_amvp_top` 内部例化关系

源码锚点：`ve_amvp_top.v::U_VC_AMVP_CTRL/U_VC_AMVP_CAND_GEN/U_CAND_OUT_FIFO/U_FME_*_CAND_FIFO/U_AMVP2CCU_FIFO/VE_IRPU_EXPG_*`。

### 3.1 `U_VC_AMVP_CTRL -> U_VC_AMVP_CAND_GEN`

| Producer | 本层中转 | Consumer | 说明 |
|---|---|---|---|
| `U_VC_AMVP_CTRL.cand_cu_start` | `[wire] cand_cu_start` | `U_VC_AMVP_CAND_GEN.cand_cu_start` | 候选生成启动 |
| `U_VC_AMVP_CTRL.cur_ref_idx` | `[wire] cur_ref_idx[3:0]` | `U_VC_AMVP_CAND_GEN.cur_ref_idx = cur_ref_idx[1:0]` | 当前 reference index，送 cand_gen 时截取低 2 bit |
| `U_VC_AMVP_CTRL.cu_blk_en` | `[wire] cu_blk_en[2:0]` | `[comb] cu_cmd_out_sel[16:14]` | 选择当前 block size |
| `U_VC_AMVP_CTRL.cu_cmd_out` | `[wire] cu_cmd_out[2:0][13:0]` | `[comb] cu_cmd_out_sel[13:0] -> cand_gen.cu_cmd_out` | 先按 `cu_blk_en` 选 command，再拼 block-size one-hot |
| `U_VC_AMVP_CTRL.blk_sz_lat` | `[wire] blk_sz_lat` | `ve_amvp_top.blk_sz_lat` | 向上一层透传，最终到 Neighbor |
| `U_VC_AMVP_CTRL.n_blk_sz` | `[wire] n_blk_sz` | `ve_amvp_top.n_blk_sz` | 向上一层透传，最终到 Neighbor |
| `U_VC_AMVP_CTRL.neib_cu_start` | 直接到本模块 output | `ve_mvp_top.amvp_neib_cu_start` | 向 Neighbor 发起读取 |

### 3.2 `U_VC_AMVP_CAND_GEN -> U_VC_AMVP_CTRL`

| Producer | `[wire]` | Consumer |
|---|---|---|
| `cand_blk_done` | `cand_blk_done` | `U_VC_AMVP_CTRL.cand_blk_done` |
| `cand_blk_idle` | `cand_blk_idle` | `U_VC_AMVP_CTRL.cand_blk_idle` |

这是 AMVP scheduler 与 candidate FSM 的闭环握手。

### 3.3 Candidate Generator -> Candidate FIFO

`U_VC_AMVP_CAND_GEN` 输出：

- `cand_mv[1:0][42:0]`
- `cand_rdy[1:0]`

本层并非直接把 `cand_mv` 送 FME，而是先生成 FIFO 输入：

```text
cand_rdy + cur_ref_idx + blk_sz
        -> [comb] cand_push[j][i]
cand_mv[i[0]] + cu_cmd_out_sel[16:14]
        -> [comb] cand_d[j][i][45:0]
        -> U_CAND_OUT_FIFO[j][i].d
```

FIFO 回传：

```text
U_CAND_OUT_FIFO.empty_n -> [wire] cand_empty_n[j][i]
U_CAND_OUT_FIFO.q       -> [wire] cand_q[j][i][45:0]
```

随后 `cand_pop/fme_ref_idx` 选择 `cand_q` 中的 `sel_cand_0/sel_cand_1`，再与 FME MV 计算 MVD。

### 3.4 FME -> `sht_mdl` -> AMVP MVD 计算

| 外部/本层信号 | FIFO | FIFO 输出/后级 |
|---|---|---|
| `fme2amvp_cand_mv[1][33:0]`, `mv_push[1]` | `U_FME_16_CAND_FIFO` | `mv_q[1]`, `mv_empty_n[1]`, `mv_full_n[1]` |
| `fme2amvp_cand_mv[0][33:0]`, `mv_push[0]` | `U_FME_8_CAND_FIFO` | `mv_q[0]`, `mv_empty_n[0]`, `mv_full_n[0]` |

`mv_q` 与 `cand_q` 选出的预测候选共同生成：

- `mvd_cand0[0/1]`
- `mvd_cand1[0/1]`

### 3.5 MVD -> `ve_irpu_expg_bits`

| Producer | Consumer | Output |
|---|---|---|
| `mvd_cand0[0]` | `VE_IRPU_EXPG_MVD_CAND0_X.val_in` | `mvd_cost0[0]` |
| `mvd_cand0[1]` | `VE_IRPU_EXPG_MVD_CAND0_Y.val_in` | `mvd_cost0[1]` |
| `mvd_cand1[0]` | `VE_IRPU_EXPG_MVD_CAND1_X.val_in` | `mvd_cost1[0]` |
| `mvd_cand1[1]` | `VE_IRPU_EXPG_MVD_CAND1_Y.val_in` | `mvd_cost1[1]` |

这里是纯组合子模块：`val_in -> val_out`，无时钟握手。

### 3.6 AMVP -> CCU FIFO

`irpu_amvp_wd` 是本层组合出的 CCU payload，送入每个 `U_AMVP2CCU_FIFO[i]`：

```text
amvp2ccu_push[i] -> FIFO.push
irpu_amvp_wd     -> FIFO.d
irpu_amvp_hsk[i] -> FIFO.pop
FIFO.empty_n     -> irpu_amvp_rdy[i]
FIFO.q           -> irpu_amvp_rd[i]
```

`irpu_amvp_rdy/rd` 再由 `ve_amvp_top` 输出到 `ve_mvp_top` 顶层端口。

---

## 4. `ve_mrg_top` 内部例化关系

源码锚点：`ve_mrg_top.v::U_VC_MRG_CTRL/U_VC_MRG_CAND_GEN/U_CAND_OUT_FIFO/U_MRG2CCU_FIFO`。

### 4.1 `U_VC_MRG_CTRL <-> U_VC_MRG_CAND_GEN`

| Producer | 本层中转 | Consumer | 说明 |
|---|---|---|---|
| `U_VC_MRG_CTRL.cand_cu_start` | `[wire] cand_cu_start` | `U_VC_MRG_CAND_GEN.cand_cu_start` | candidate start |
| `U_VC_MRG_CTRL.cur_ref_idx` | `[wire] cur_ref_idx[3:0]` | `U_VC_MRG_CAND_GEN.cur_ref_idx[1:0]` | 当前 ref |
| `U_VC_MRG_CTRL.cu_blk_en/cu_cmd_out` | `[wire]` + `[comb] cu_cmd_out_sel` | `U_VC_MRG_CAND_GEN.cu_cmd_out` | 先把 14-bit command 与 one-hot block size 合并为 17 bit |
| `U_VC_MRG_CAND_GEN.cand_blk_done` | `[wire] cand_blk_done` | `U_VC_MRG_CTRL.cand_blk_done` | candidate 完成反馈 |
| `U_VC_MRG_CAND_GEN.cand_blk_idle` | `[wire] cand_blk_idle` | `U_VC_MRG_CTRL.cand_blk_idle` | candidate idle 反馈 |

`U_VC_MRG_CTRL` 同时向上一层输出 `cu_blk_en`、`cu_cmd_out`、`neib_cu_start`、`cmdq_empty_n`、`blk_sz_lat`、`n_blk_sz`，再由 `ve_mvp_top` wire 接到 `vc_mvp_get_neib`。

### 4.2 Merge Candidate FIFO

`U_VC_MRG_CAND_GEN` 产生 `cand_mv/cand_rdy`，本层生成 `cand_push/cand_d` 后进入 6 个 `U_CAND_OUT_FIFO`：

```text
cand_mv/cand_rdy
 -> [comb] cand_push[5:0], cand_d[5:0][45:0]
 -> U_CAND_OUT_FIFO[]
 -> cand_empty_n[5:0], cand_q[5:0][45:0]
 -> Merge flow / MC candidate selection
```

注释定义索引：0/1=blk8 cand0/cand1，2/3=blk16，4/5=blk32。

### 4.3 Merge <-> MC 为顶层直通接口，不再经过子模块

`mrg2mc_cand_rdy/data/nb`、`mrg2mc_cost_ack` 与 `mc2mrg_cand_ack/cost_rdy/cost_data` 都在 `ve_mrg_top` 本层 FSM/组合逻辑处理，然后直接通过 `ve_mvp_top` 顶层端口对外。

因此该路径不存在“另一个 MC 子模块实例”。

### 4.4 Merge -> CCU FIFO

每个 block-size 对应一个 `U_MRG2CCU_FIFO[i]`：

```text
mrg2ccu_push[i] -> FIFO.push
irpu_mrg_wd[i]  -> FIFO.d
irpu_mrg_hsk[i] -> FIFO.pop
FIFO.empty_n    -> irpu_mrg_rdy[i]
FIFO.q          -> irpu_mrg_rd[i]
```

---

## 5. `vc_mvp_cand_gen` 内部例化关系

### 5.1 `vc_mvp_cand_prior`

`U_VC_MVP_CAND_PRIOR` 是规则判断层。

```text
cand_gen 内部解析的 availability / POC / long-term / col 信息
   -> U_VC_MVP_CAND_PRIOR inputs
   -> cand_a[AW-1:0], cand_b[BW-1:0], cand_c[3:0]
   -> cand_gen FSM/one-hot candidate selection
```

关键中转信号：`a0_avail/a1_avail/b0_avail/b1_avail/b2_avail`、`c0_avail/c1_avail`、`n_cur_poc_diff`、`cur_ref_poc/ref_long`、各 A/B POC/long、C0/C1 pocdiff/intra/long。

### 5.2 `vc_mvp_scale`

仅当 `MVP_SCALE_EN` generate 分支成立时例化 `U_VC_SCALE_CAL`。

| `vc_mvp_cand_gen` -> Scale | Scale -> `vc_mvp_cand_gen` |
|---|---|
| `scale_start` | `scale_done` |
| `mvx_sel -> n_mvx` | `scale_mvx` |
| `mvy_sel -> n_mvy` | `scale_mvy` |
| `n_cur_poc_diff` |  |
| `sel_poc_diff -> n_col_poc_diff` |  |

这些输出回到同一个 `vc_mvp_cand_gen` FSM，用于填充 scaled candidate；不是直接跨到 AMVP/Merge top。

---

## 6. `vc_mvp_ctrl` 内部 `sht_mdl` command queue

`vc_mvp_ctrl` 对每个 block-size generate 一个 `ccu_cmdq`。

```text
cur_cu_* inputs
 -> [comb] cu_cmdq_in[sz][13:0]
 -> ccu_cmdq[sz].d

push[sz] -> ccu_cmdq.push
pop[sz]  -> ccu_cmdq.pop

ccu_cmdq.q       -> cu_cmdq_out[sz] -> module output cu_cmd_out[sz]
ccu_cmdq.empty_n -> empty_n[sz]     -> parent AMVP/Merge top
```

AMVP 与 Merge 使用同一个模块，但 `AMVP_OR_MRG` 参数改变 `push/pop/ref` 控制条件。

`cu_cmdq_in[13:0]` 当前布局由 RTL 直接拼接为：

```text
[13]    terminate
[12]    skip
[11]    zmv
[10:9]  A availability
[8:6]   B availability
[5:3]   cur_cu_y
[2:0]   cur_cu_x
```

---

## 7. `vc_mvp_get_neib`：四个 `vc_mvp_rd_mem` 与外部 Memory 的关系

这是最容易误读的中转路径：**`vc_mvp_rd_mem` 不接收实际 neighbor data，只接收 `gnt/rd_lat`；实际 `*_rd` 数据由 `vc_mvp_get_neib` 本层消费。**

### 7.1 A reader `U_GET_NEIB_A`

```text
neib_a_cu_start / a_avail_cnt / cux/cuy/ctu
  -> U_GET_NEIB_A

U_GET_NEIB_A.ip2mem_req  -> irpu2neib_a_req
U_GET_NEIB_A.ip2mem_addr -> irpu2neib_a_addr_full
                         -> [slice 2:1] irpu2neib_a_addr
U_GET_NEIB_A.cmdq2ip_info -> neib_a_info[2:0]
U_GET_NEIB_A.rd_mem_idle  -> get_neib_a_idle

neib_a2irpu_gnt/rd_lat -> U_GET_NEIB_A
neib_a2irpu_rd         -> vc_mvp_get_neib 本层缓存逻辑
neib_a_info + rd_lat   -> 判断本拍返回数据写入哪个 A set
```

### 7.2 B reader `U_GET_NEIB_B`

```text
neib_b_cu_start / b_avail_cnt / cux/cuy/ctu
  -> U_GET_NEIB_B

U_GET_NEIB_B.ip2mem_req  -> irpu2neib_b_req
U_GET_NEIB_B.ip2mem_addr -> irpu2neib_b_addr_full
                         -> [slice 5:1] irpu2neib_b_addr
U_GET_NEIB_B.cmdq2ip_info -> neib_b_info[3:0]
U_GET_NEIB_B.rd_mem_idle  -> get_neib_b_idle

neib_b2irpu_gnt/rd_lat -> U_GET_NEIB_B
neib_b2irpu_rd         -> vc_mvp_get_neib 本层缓存逻辑
neib_b_info + rd_lat   -> 判断本拍返回数据写入哪个 B set
```

### 7.3 Colocated reader `U_GET_NEIB_C`

```text
neib_c_cu_start / c_avail_cnt
  -> U_GET_NEIB_C

ip2mem_req  -> irpu2col_req
ip2mem_addr -> irpu2col_addr_full -> [5:1] irpu2col_addr
cmdq2ip_info -> col_c_info[2:0]
rd_mem_idle  -> get_neib_c_idle

col2irpu_gnt/rd_lat -> U_GET_NEIB_C
col2irpu_rd         -> vc_mvp_get_neib 本层 mvp_col_c_reg
```

### 7.4 RefList reader `U_GET_REFLIST`

```text
ctu0_start -> U_GET_REFLIST.ip_cu_start
ref_avail/ref_avail_cnt -> U_GET_REFLIST

ip2mem_req   -> irpu2ref_req
ip2mem_addr  -> irpu2ref_addr
cmdq2ip_info -> ref_info[NUM_REF-1:0]
rd_mem_idle  -> get_ref_idle

ref2irpu_gnt/rd_lat -> U_GET_REFLIST
ref2irpu_rd + ref_info -> vc_mvp_get_neib.reflist_info[]
```

### 7.5 Neighbor 完成反馈

四路 reader 的 idle 状态最终组成：

```verilog
neib_done_con = (get_neib_a_idle | blk_8_start_a_con) &
                (get_neib_b_idle | blk_8_start_b_con) &
                 get_neib_c_idle & get_ref_idle;

neib_done_amvp = neib_done_con;
neib_done_mrg  = neib_done_con;
```

所以 `neib_done_amvp` 与 `neib_done_mrg` 当前值完全相同，只是分别接回 AMVP/Merge 顶层端口。

---

## 8. `vc_mvp_rd_mem -> sht_mdl`：请求 metadata 对齐 FIFO

每个 `vc_mvp_rd_mem` 内部都例化 `mem_cmd_fifo`。

RTL 中转关系：

```verilog
push = ip2mem_req & mem2ip_gnt;
pop  = mem2ip_rd_lat;
d    = ip2cmdq_info;
cmdq2ip_info = q;
```

因此一条 memory request 被 grant 时，当前 request 对应的 `info` 被压入 FIFO；等 `rd_lat` 返回时弹出 `q`。父层 `vc_mvp_get_neib` 用该 `q`（即 `neib_a_info/neib_b_info/col_c_info/ref_info`）给返回数据定归属。

这条路径是：

```text
request address/info
 -> vc_mvp_rd_mem
 -> [wire] ip2cmdq_info
 -> sht_mdl.d
 -> sht_mdl.q
 -> [wire] cmdq2ip_info
 -> vc_mvp_get_neib 返回数据写入选择
```

---

## 9. 一级 `wire` 中转索引

下面只列 `ve_mvp_top` 中真正承担同级子模块互连的关键内部 net。

| `ve_mvp_top` net | Producer | Consumer(s) |
|---|---|---|
| `amvp_neib_cu_start` | `ve_amvp_top` | `vc_mvp_get_neib` |
| `mrg_neib_cu_start` | `ve_mrg_top` | `vc_mvp_get_neib` |
| `cmdq_empty_n[1]` | `ve_amvp_top` | `vc_mvp_get_neib` |
| `cmdq_empty_n[0]` | `ve_mrg_top` | `vc_mvp_get_neib` |
| `amvp_blk_sz` | `ve_amvp_top` | `vc_mvp_get_neib` |
| `mrg_blk_sz` | `ve_mrg_top` | `vc_mvp_get_neib` |
| `amvp_cmd_out` | `ve_amvp_top` | `vc_mvp_get_neib` |
| `mrg_cmd_out` | `ve_mrg_top` | `vc_mvp_get_neib` |
| `neib_done_amvp` | `vc_mvp_get_neib` | `ve_amvp_top` |
| `neib_done_mrg` | `vc_mvp_get_neib` | `ve_mrg_top` |
| `amvp_neib_a/b`, `amvp_col_c`, `amvp_col_c_avail` | `vc_mvp_get_neib` | `ve_amvp_top` |
| `mrg_neib_a/b`, `mrg_col_c`, `mrg_col_c_avail` | `vc_mvp_get_neib` | `ve_mrg_top` |
| `reflist_info` | `vc_mvp_get_neib` | `ve_amvp_top`, `ve_mrg_top` |
| `blk*_neib_*_r` | `vc_mvp_get_neib` | `ve_amvp_top`, `ve_mrg_top` |
| `avc_mvp_push/ref_idx/is_long/pocdiff/mvpxy/mvd_gt4` | `ve_amvp_top` | `ve_mrg_top` |
| `blk_sz_lat_amvp/n_blk_sz_amvp` | `ve_amvp_top` | `vc_mvp_get_neib` |
| `blk_sz_lat_mrg/n_blk_sz_mrg` | `ve_mrg_top` | `vc_mvp_get_neib` |

---

## 10. 当前 RTL 中需要单独复核的连接风险

### R1. `irpu2neib_*_req` 位宽声明不一致

当前源码直接可见：

- `ve_mvp_top.irpu2neib_b_req`：顶层声明为 **1 bit**。
- `vc_mvp_get_neib.irpu2neib_b_req`：声明为 **[4:0]**。
- `vc_mvp_rd_mem.ip2mem_req`：声明为 **1 bit**。

A 路同样存在：

- `ve_mvp_top.irpu2neib_a_req`：**1 bit**。
- `vc_mvp_get_neib.irpu2neib_a_req`：**[1:0]**。
- `vc_mvp_rd_mem.ip2mem_req`：**1 bit**。

本文不猜测设计意图。该处属于实际端口宽度 mismatch，建议编译 warning / 波形确认后再决定是否应把 `vc_mvp_get_neib` 的 req 改回 scalar，或顶层接口应扩宽。

### R2. Merge Neighbor start 端口连接但当前未成为有效启动源

见 2.7：`mrg_cu_start` 已接入 `vc_mvp_get_neib`，但 `cmdq_cu_start` 当前固定等于 `amvp_cu_start`。

### R3. Merge 的 `reg_i_slice` 是顶层加工后的 `g_reg_i_slice`

```verilog
assign g_reg_i_slice = reg_avc_mode | reg_i_slice;
```

所以在 `reg_avc_mode=1` 时，`ve_mrg_top.reg_i_slice` 被强制为 1。分析 AVC 路径时不能按“Merge 收到原始 `reg_i_slice`”理解。

---

## 11. 最短数据流总结

### AMVP 主链

```text
CU/CTU input
 -> ve_amvp_top/U_VC_AMVP_CTRL
 -> amvp_neib_cu_start + amvp_cmd_out/amvp_blk_sz
 -> vc_mvp_get_neib
 -> A/B/Col/RefList
 -> ve_amvp_top/U_VC_AMVP_CAND_GEN
 -> vc_mvp_cand_prior (+ vc_mvp_scale when enabled)
 -> cand_mv/cand_rdy
 -> candidate FIFO
 -> FME MV + MVP candidate -> MVD
 -> ve_irpu_expg_bits cost
 -> AMVP2CCU FIFO
 -> irpu_amvp_rdy/rd
```

### Merge 主链

```text
CU/CTU input
 -> ve_mrg_top/U_VC_MRG_CTRL
 -> mrg_cmd_out/mrg_blk_sz
 -> shared vc_mvp_get_neib data
 -> ve_mrg_top/U_VC_MRG_CAND_GEN
 -> vc_mvp_cand_prior (+ vc_mvp_scale when enabled)
 -> cand_mv/cand_rdy
 -> candidate FIFO
 -> MC candidate output / MC cost feedback
 -> MRG2CCU FIFO
 -> irpu_mrg_rdy/rd
```

### Neighbor Memory 主链

```text
AMVP/command state
 -> vc_mvp_get_neib
 -> vc_mvp_rd_mem request/address
 -> external Neighbor/Col/Ref memory
 -> gnt/rd_lat
 -> vc_mvp_rd_mem metadata FIFO
 -> info tag
 + external rd data
 -> vc_mvp_get_neib cache/select
 -> AMVP/Merge
```

---

## 12. 源码复核入口

优先按以下实例名定位，不依赖会随修改漂移的行号：

1. `ve_mvp_top.v`: `U_VE_AMVP_TOP`, `U_VE_MRG_TOP`, `U_VC_MVP_GET_NEIB`
2. `ve_amvp_top.v`: `U_VC_AMVP_CTRL`, `U_VC_AMVP_CAND_GEN`, `U_CAND_OUT_FIFO`, `U_FME_*_CAND_FIFO`, `U_AMVP2CCU_FIFO`, `VE_IRPU_EXPG_*`
3. `ve_mrg_top.v`: `U_VC_MRG_CTRL`, `U_VC_MRG_CAND_GEN`, `U_CAND_OUT_FIFO`, `U_MRG2CCU_FIFO`
4. `vc_mvp_get_neib.v`: `U_GET_NEIB_A`, `U_GET_NEIB_B`, `U_GET_NEIB_C`, `U_GET_REFLIST`
5. `vc_mvp_cand_gen.v`: `U_VC_MVP_CAND_PRIOR`, `U_VC_SCALE_CAL`
6. `vc_mvp_ctrl.v`: `ccu_cmdq`
7. `vc_mvp_rd_mem.v`: `mem_cmd_fifo`

如果后续要画模块互连图，应直接以上述表格作为网表依据，不从功能经验反推连线。
