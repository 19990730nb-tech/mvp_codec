# MVP Architecture 节点与连接清单

本清单由视觉优化前的 `figures/mvp_arch.dot` 提取，是新版架构图的语义核对基线。节点标签中的 `\n` 表示原图换行；未标注标签的连线保持无标签。

## 节点与层级

### `vc_mvp_top` 外部节点

```text
cfg : REG / CTU / CU\nconfiguration and commands
mem : External neighbor memories\nA / B / Col / Ref-list
fme : FME
ccu : CCU
mc  : MC
```

### `vc_mvp_top`

```text
mux : codec_mode MC mux\nencoder Merge / AVC decoder
```

### `ve_mrg_top (encoder Merge, PU8/16/32)`

```text
mrg_ctrl : vc_mvp_ctrl\nAMVP_OR_MRG=0\n3 command FIFOs
mrg_gen  : vc_mvp_cand_gen\nAMVP_OR_MRG=0
mrg_fifo : Per-PU candidate FIFOs\n6 flow FSMs / 3 MC-done FSMs
mrg_out  : MC and CCU result queues
```

### `vc_amvp_top (AMVP encoder + AVC decoder)`

```text
amvp_ctrl  : vc_mvp_ctrl\nAMVP_OR_MRG=1\n2 command FIFOs (default)
amvp_gen   : vc_mvp_cand_gen\nAMVP_OR_MRG=1
rendezvous : Per-PU/ref/candidate slots\n+ PU8/PU16 MV/MVD FIFOs
dec_hold   : AVC decoder transaction flags\nMVP + MVD result hold
amvp_out   : AMVP CCU queues\nAVC encoder bridge
```

### `vc_mvp_get_neib (physically shared)`

```text
rdmem : 4 x vc_mvp_rd_mem\nA / B / Col / Ref
cache : A/B/Col staging registers\nwithin-CTU A/B history
```

## 有向及双向连接

`<->` 对应原 DOT 的 `dir=both`；其余连接均保持原 DOT 的单向箭头。

```text
mrg_ctrl -> mrg_gen : "cand_cu_start / blk select"
mrg_gen -> mrg_fifo : "cand_rdy[1:0], cand_mv"
mrg_fifo -> mrg_out : "candidate / MC cost"

amvp_ctrl -> amvp_gen : "cand_cu_start / ref / blk"
amvp_gen -> rendezvous : "cand_rdy[1:0], cand_mv"
rendezvous -> amvp_out : "encoder join"
rendezvous -> dec_hold : "AVC decoder join"

rdmem -> cache : "read data + destination metadata"

cfg -> mrg_ctrl : <no label>
cfg -> amvp_ctrl : <no label>
cfg -> cache : "CU update"

amvp_ctrl -> rdmem : "cmdq_cu_start (active trigger)"
mrg_ctrl -> rdmem : "non-AVC size context"
rdmem <-> mem : "req/gnt + rd_lat/data"
cache -> mrg_gen : "neib/col/ref"
cache -> amvp_gen : "neib/col/ref"
rdmem -> mrg_ctrl : "neib_done"
rdmem -> amvp_ctrl : "neib_done"

fme <-> rendezvous : "PU8/16 MV + ack"
amvp_out -> ccu : "irpu_amvp_*"
mrg_out -> ccu : "irpu_mrg_*"
mrg_out -> mux : "encoder candidates"
dec_hold -> mux : "decoded MV"
mux <-> mc : "mrg2mc_* / mc2mrg_ack"
dec_hold -> cache : "update on dec_mc_accept"
amvp_out -> mrg_fifo : "AVC encoder avc_mvp_*"
```

## 核对基数

- 节点：17 个。
- 子模块簇：`vc_mvp_top`、`ve_mrg_top`、`vc_amvp_top`、`vc_mvp_get_neib`。
- 连接：26 条，其中 3 条为 `dir=both` 双向连接。
