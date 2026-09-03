from pathlib import Path
from textwrap import dedent
import cairosvg

OUT = Path('/mnt/data/avc_decoder_mvp_spec')
OUT.mkdir(exist_ok=True)

# ---------- SVG helpers ----------
def svg_header(w,h,title):
    return f'''<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" viewBox="0 0 {w} {h}">
  <title>{title}</title>
  <rect x="0" y="0" width="{w}" height="{h}" fill="#ffffff"/>
  <defs>
    <marker id="arrow" markerWidth="8" markerHeight="8" refX="7" refY="4" orient="auto" markerUnits="strokeWidth">
      <path d="M0,0 L8,4 L0,8 z" fill="#263238"/>
    </marker>
    <marker id="arrowDash" markerWidth="8" markerHeight="8" refX="7" refY="4" orient="auto" markerUnits="strokeWidth">
      <path d="M0,0 L8,4 L0,8 z" fill="#607d8b"/>
    </marker>
    <style>
      .title {{ font: 700 22px Arial, 'Microsoft YaHei', sans-serif; fill:#111; }}
      .boxTitle {{ font: 700 15px Arial, 'Microsoft YaHei', sans-serif; fill:#111; }}
      .txt {{ font: 13px Arial, 'Microsoft YaHei', sans-serif; fill:#222; }}
      .small {{ font: 12px Arial, 'Microsoft YaHei', sans-serif; fill:#333; }}
      .tiny {{ font: 11px Arial, 'Microsoft YaHei', sans-serif; fill:#444; }}
      .reuse {{ fill:#eef3f5; stroke:#37474f; stroke-width:1.5; rx:8; }}
      .new {{ fill:#f7f7f7; stroke:#111; stroke-width:2; rx:8; }}
      .ext {{ fill:#fff; stroke:#607d8b; stroke-width:1.5; rx:8; }}
      .bypass {{ fill:#fafafa; stroke:#9e9e9e; stroke-width:1.2; stroke-dasharray:6 5; rx:8; }}
      .lane {{ fill:#ffffff; stroke:#90a4ae; stroke-width:1; rx:6; }}
      .arrow {{ fill:none; stroke:#263238; stroke-width:1.8; marker-end:url(#arrow); }}
      .arrow2 {{ fill:none; stroke:#263238; stroke-width:1.4; marker-end:url(#arrow); }}
      .dash {{ fill:none; stroke:#607d8b; stroke-width:1.4; stroke-dasharray:6 5; marker-end:url(#arrowDash); }}
      .feedback {{ fill:none; stroke:#455a64; stroke-width:1.6; marker-end:url(#arrow); }}
    </style>
  </defs>
'''

def rect(x,y,w,h,cls='reuse'):
    return f'<rect x="{x}" y="{y}" width="{w}" height="{h}" class="{cls}"/>'

def text(x,y,s,cls='txt',anchor='start'):
    return f'<text x="{x}" y="{y}" class="{cls}" text-anchor="{anchor}">{s}</text>'

def multiline(x,y,lines,cls='small',dy=17,anchor='middle'):
    parts=[f'<text x="{x}" y="{y}" class="{cls}" text-anchor="{anchor}">']
    for i,l in enumerate(lines):
        parts.append(f'<tspan x="{x}" dy="{0 if i==0 else dy}">{l}</tspan>')
    parts.append('</text>')
    return ''.join(parts)

def line(x1,y1,x2,y2,cls='arrow'):
    return f'<path d="M{x1},{y1} L{x2},{y2}" class="{cls}"/>'

def poly(points, cls='arrow'):
    d='M'+' L'.join(f'{x},{y}' for x,y in points)
    return f'<path d="{d}" class="{cls}"/>'

# ---------- Figure 1: overall architecture ----------
w,h=1600,1040
s=[svg_header(w,h,'AVC Decoder MVP Overall Architecture')]
s.append(text(800,38,'AVC Decoder MVP — Proposed Architecture / Data Flow','title','middle'))
s.append(text(800,62,'solid = decoder active path; dashed = encoder-only / dormant in AVC decode','tiny','middle'))

# external blocks
s.append(rect(40,110,260,160,'ext'))
s.append(multiline(170,140,['CCU / Parser / NMU','decoded syntax + context'],'boxTitle',20))
s.append(multiline(170,190,['mode / cux,cuy / sub_idx','ref_idx_l0 / MVD / skip','A/B availability'],'small',18))

s.append(rect(40,720,260,150,'ext'))
s.append(multiline(170,750,['MVB SRAM','spatial motion neighbor'],'boxTitle',20))
s.append(multiline(170,802,['A/B read data','gnt / rd_lat'],'small',18))

s.append(rect(1260,120,285,170,'ext'))
s.append(multiline(1402,150,['CCU Decoder Inter Path'],'boxTitle',20))
s.append(multiline(1402,195,['consume final MV/ref_idx','issue MC command','generate cur_cu_upd'],'small',18))

s.append(rect(1260,390,285,120,'ext'))
s.append(multiline(1402,420,['MC Subsystem'],'boxTitle',20))
s.append(multiline(1402,462,['motion compensation','decoder prediction'],'small',18))

s.append(rect(1260,720,285,155,'ext'))
s.append(multiline(1402,750,['NMU / Writeback'],'boxTitle',20))
s.append(multiline(1402,800,['same-CTU buffer update','row buffer → DMA → MVB'],'small',18))

# decoder blocks
s.append(rect(360,105,255,175,'new'))
s.append(multiline(488,136,['DEC_CTRL  [NEW]'],'boxTitle',20))
s.append(multiline(488,181,['input rendezvous','P16 / P8 S0→S3 scheduler','17-bit command context','no ref traversal'],'small',18))

s.append(rect(350,355,420,340,'reuse'))
s.append(multiline(560,382,['vc_mvp_get_neib  [REUSE]'],'boxTitle',20))
# internals
s.append(rect(380,420,165,86,'lane'))
s.append(multiline(462,445,['vc_mvp_rd_mem A'],'small',18))
s.append(multiline(462,480,['req/gnt/rd_lat'],'tiny',16))
s.append(rect(575,420,165,86,'lane'))
s.append(multiline(657,445,['vc_mvp_rd_mem B'],'small',18))
s.append(multiline(657,480,['req/gnt/rd_lat'],'tiny',16))
s.append(rect(380,535,360,132,'lane'))
s.append(multiline(560,558,['Neighbor View'],'small',18))
s.append(multiline(560,590,['mvp_neib_a/b_reg  snapshot','a_0_reg / b_0_reg rolling','buf_reg corner assist'],'tiny',17))

s.append(rect(835,350,300,230,'reuse'))
s.append(multiline(985,380,['vc_mvp_cand_gen  [REUSE MED]'],'boxTitle',20))
s.append(multiline(985,426,['A = neib_a[1]','B = neib_b[1]','C = neib_b[0] / b2 fallback','component-wise signed median'],'small',18))
s.append(text(985,548,'MVP = cand_mv[0][31:0]','small','middle'))

s.append(rect(835,610,300,190,'new'))
s.append(multiline(985,642,['DEC_RECON  [NEW]'],'boxTitle',20))
s.append(multiline(985,685,['Inter: final MV = MVP + MVD','P_SKIP: zero-special ? 0 : MVP','carry parsed ref_idx_l0'],'small',19))
s.append(text(985,770,'result held until downstream accept','tiny','middle'))

# dormant/bypass blocks
s.append(rect(835,845,300,110,'bypass'))
s.append(multiline(985,875,['Dormant / bypass in AVC decode'],'small',18))
s.append(multiline(985,910,['vc_mvp_cand_prior / vc_mvp_scale','Colocated read / FME / ve_mrg_top cost path'],'tiny',16))

# arrows/data labels
s.append(line(300,190,360,190,'arrow'))
s.append(text(330,178,'valid/ready','tiny','middle'))

s.append(poly([(488,280),(488,330),(560,330),(560,355)],'arrow'))
s.append(text(520,320,'neib_start + cmd','tiny','middle'))

s.append(poly([(615,215),(785,215),(785,405),(835,405)],'arrow'))
s.append(text(720,203,'cand_start + command','tiny','middle'))

s.append(line(770,500,835,500,'arrow'))
s.append(text(800,487,'A/B neighbor','tiny','middle'))

s.append(line(985,580,985,610,'arrow'))
s.append(text(1012,600,'MVP','tiny'))

s.append(poly([(615,250),(770,250),(770,700),(835,700)],'arrow'))
s.append(text(730,238,'MVD / ref_idx / skip','tiny','middle'))

s.append(line(1135,700,1260,205,'arrow'))
s.append(text(1194,446,'final MV + ref_idx','tiny','middle'))

s.append(line(1402,290,1402,390,'arrow'))
s.append(text(1430,344,'MC cmd','tiny'))

# feedback cur_cu_upd from CCU to neighbor + NMU
s.append(poly([(1260,245),(1200,245),(1200,675),(770,675)],'feedback'))
s.append(text(1085,662,'cur_cu_upd(final MV)','tiny','middle'))
s.append(line(1402,290,1402,720,'feedback'))
s.append(text(1435,620,'cur_cu_upd','tiny'))

# MVB read and writeback
s.append(poly([(300,795),(325,795),(325,475),(350,475)],'arrow'))
s.append(text(328,665,'A/B read','tiny'))
s.append(poly([(1260,810),(1170,810),(1170,930),(170,930),(170,870)],'feedback'))
s.append(text(700,920,'row-end DMA writeback','tiny','middle'))

# show P8 internal dependency note
s.append(rect(350,735,420,130,'ext'))
s.append(multiline(560,760,['P8 intra-CU dependency'],'small',18))
s.append(multiline(560,795,['S0 commit → S1/S2','S1 commit → S2/S3','S2 commit → S3'],'tiny',17))
s.append(poly([(770,800),(800,800),(800,620),(770,620)],'feedback'))
s.append(text(805,760,'rolling MV','tiny'))

# architecture note
s.append(rect(40,915,260,90,'bypass'))
s.append(multiline(170,942,['Decoder principle'],'small',18))
s.append(multiline(170,975,['reuse spatial neighbor + MED','remove encoder search / RDO'],'tiny',16))

s.append('</svg>')
svg1=''.join(s)
(OUT/'fig1_avc_decoder_mvp_arch.svg').write_text(svg1,encoding='utf-8')
cairosvg.svg2png(bytestring=svg1.encode(), write_to=str(OUT/'fig1_avc_decoder_mvp_arch.png'), output_width=w, output_height=h)

# ---------- Figure 2: P8 sequence ----------
w,h=1500,880
s=[svg_header(w,h,'AVC Decoder P8x8 Transaction and Neighbor Dependency')]
s.append(text(750,38,'AVC P8×8 — Serial Transaction / Neighbor Dependency','title','middle'))
s.append(text(750,62,'AVC test condition: reg_tmp_mvp_flag = 0 → no colocated SRAM read','tiny','middle'))

# top source lanes
s.append(rect(50,100,250,105,'ext'))
s.append(multiline(175,130,['MVB SRAM → snapshot'],'boxTitle',18))
s.append(multiline(175,165,['mvp_neib_a_reg','mvp_neib_b_reg'],'small',16))
s.append(rect(1200,100,250,105,'ext'))
s.append(multiline(1325,130,['CCU final MV commit'],'boxTitle',18))
s.append(multiline(1325,165,['cur_cu_upd pulse'],'small',16))

# stages
xs=[80,430,780,1130]
labels=['S0 / 8_0','S1 / 8_1','S2 / 8_2','S3 / 8_3']
reads=['A×2 + B×2 = 4','B×2 = 2','A×2 = 2','SRAM read = 0']
sources=[
    ['A: snapshot','B/C/B2: snapshot'],
    ['A: a_0_reg(S0)','B/C/B2: snapshot'],
    ['A: snapshot','B: b_0_reg(S0)','C: b_0_reg(S1)','B2: buf/rolling case'],
    ['A: a_0_reg(S2)','B: b_0_reg(S1)','C/B2: rolling/boundary case']
]
for i,x in enumerate(xs):
    s.append(rect(x,300,280,300,'new'))
    s.append(text(x+140,332,labels[i],'boxTitle','middle'))
    s.append(text(x+140,370,reads[i],'small','middle'))
    yy=415
    for src in sources[i]:
        s.append(text(x+28,yy,src,'small'))
        yy+=28
    s.append(text(x+140,545,'MED → MVP → +MVD','small','middle'))
    s.append(text(x+140,575,'final MV','boxTitle','middle'))

# serial arrows
for i in range(3):
    s.append(line(xs[i]+280,450,xs[i+1],450,'arrow'))
    s.append(text((xs[i]+280+xs[i+1])/2,435,'next after commit','tiny','middle'))

# snapshot feeds
for i,x in enumerate(xs[:3]):
    s.append(poly([(175,205),(175,250),(x+140,250),(x+140,300)],'arrow2'))

# update loop from each stage to rolling regs band
s.append(rect(390,680,720,115,'reuse'))
s.append(multiline(750,710,['IRPU rolling neighbor registers'],'boxTitle',18))
s.append(multiline(750,748,['a_0_reg / b_0_reg (+ buf_reg corner assist)'],'small',18))
s.append(text(750,778,'written by cur_cu_upd(final MV), no handshake','tiny','middle'))
for i,x in enumerate(xs[:3]):
    s.append(poly([(x+140,600),(x+140,650),(600+i*130,650),(600+i*130,680)],'feedback'))

# rolling feed to later blocks
s.append(poly([(650,680),(650,640),(570,640),(570,600)],'feedback'))
s.append(poly([(750,680),(750,630),(920,630),(920,600)],'feedback'))
s.append(poly([(850,680),(850,620),(1270,620),(1270,600)],'feedback'))

# CCU commit relation
s.append(poly([(1325,205),(1325,265),(1450,265),(1450,740),(1110,740)],'feedback'))
s.append(text(1378,253,'commit source','tiny','middle'))

# note
s.append(rect(50,680,285,115,'bypass'))
s.append(multiline(192,710,['Important'],'small',18))
s.append(multiline(192,745,['S0→S1→S2→S3 serial','later blocks consume reconstructed final MV'],'tiny',16))

s.append('</svg>')
svg2=''.join(s)
(OUT/'fig2_p8_serial_neighbor_flow.svg').write_text(svg2,encoding='utf-8')
cairosvg.svg2png(bytestring=svg2.encode(), write_to=str(OUT/'fig2_p8_serial_neighbor_flow.png'), output_width=w, output_height=h)

# ---------- Figure 3: mode derivation ----------
w,h=1400,760
s=[svg_header(w,h,'AVC Decoder Motion Vector Derivation')]
s.append(text(700,38,'AVC Decoder — P16/P8 vs P_SKIP MV Derivation','title','middle'))

s.append(rect(50,110,240,110,'ext'))
s.append(multiline(170,140,['A/B spatial neighbors'],'boxTitle',18))
s.append(multiline(170,180,['snapshot + rolling regs'],'small',16))

s.append(rect(380,105,280,180,'reuse'))
s.append(multiline(520,136,['AVC MED predictor'],'boxTitle',18))
s.append(multiline(520,178,['A = a1','B = b1','C = b0 / b2 fallback'],'small',18))
s.append(text(520,250,'MVP','boxTitle','middle'))

s.append(line(290,165,380,165,'arrow'))

# inter branch
s.append(rect(760,90,260,230,'new'))
s.append(multiline(890,122,['P16 / P8 Inter'],'boxTitle',18))
s.append(multiline(890,165,['decoded MVD','signed add'],'small',18))
s.append(text(890,220,'final MV = MVP + MVD','boxTitle','middle'))
s.append(text(890,270,'ref_idx_l0 carried separately','small','middle'))
s.append(line(660,190,760,190,'arrow'))

# skip branch
s.append(rect(760,405,260,230,'new'))
s.append(multiline(890,438,['P_SKIP'],'boxTitle',18))
s.append(multiline(890,480,['zero-motion special rule','else use MED MVP'],'small',18))
s.append(text(890,535,'final MV = 0 or MVP','boxTitle','middle'))
s.append(text(890,585,'no decoded MVD','small','middle'))
s.append(poly([(660,225),(700,225),(700,520),(760,520)],'arrow'))

# output
s.append(rect(1120,250,230,210,'ext'))
s.append(multiline(1235,282,['Decoder result'],'boxTitle',18))
s.append(multiline(1235,326,['final MV','ref_idx_l0','position / size'],'small',18))
s.append(text(1235,410,'→ CCU → MC','boxTitle','middle'))
s.append(line(1020,220,1120,305,'arrow'))
s.append(line(1020,535,1120,405,'arrow'))

# no encoder blocks note
s.append(rect(50,500,610,135,'bypass'))
s.append(multiline(355,530,['Not used in decoder MV derivation'],'small',18))
s.append(multiline(355,568,['IME/FME search · FME SATD · reference traversal · vc_mvp_scale · ve_mrg_top cost/RDO'],'tiny',17))

s.append('</svg>')
svg3=''.join(s)
(OUT/'fig3_mode_mv_derivation.svg').write_text(svg3,encoding='utf-8')
cairosvg.svg2png(bytestring=svg3.encode(), write_to=str(OUT/'fig3_mode_mv_derivation.png'), output_width=w, output_height=h)

# ---------- Markdown spec ----------
spec = dedent(r'''
# AVC Decoder MVP Architecture Spec — v0.1

> Status: **architecture draft based on verified encoder RTL + AVC waveform findings already discussed**.  
> Scope: AVC P16×16, P8×8, P_SKIP motion-vector derivation and neighbor dependency.  
> Non-goal: HEVC AMVP/Merge decoder, B-slice/List1, encoder RDO/FME.

## 0. Source-of-truth rule

The decoder architecture is derived from the current encoder reference RTL. Old decoder attempts and the previous design-spec document are **not** used as implementation authority.

Primary source files:

- `ve_mvp_top.v`
- `ve_amvp_top.v`
- `ve_mrg_top.v`
- `vc_mvp_ctrl.v`
- `vc_mvp_get_neib.v`
- `vc_mvp_rd_mem.v`
- `vc_mvp_cand_gen.v`
- `vc_mvp_cand_prior.v`
- `vc_mvp_scale.v`
- `sht_mdl.v`

H.264 algorithm reference: Richardson, *The H.264 Advanced Video Compression Standard*, Ch. 6.4.3–6.4.4.

---

## 1. Frozen conclusions

### 1.1 Decoder equation

For AVC transmitted Inter partitions:

`final_MV = MVP + decoded_MVD`

For P_SKIP:

`final_MV = 0` when the project RTL zero-motion special condition is true; otherwise `final_MV = MVP`.

The H.264 decoder forms the same predictor MVp as the encoder and adds the decoded MVD; skipped macroblocks have no decoded vector difference and use the derived predictor directly.

### 1.2 AVC predictor

AVC uses the `MED` path in `vc_mvp_cand_gen`:

- A = `neib_a[1]`
- B = `neib_b[1]`
- C = `neib_b[0]`, with `neib_b[2]` fallback when B0 is unavailable
- X/Y are independently signed-median selected
- no AVC ref-index matching/scaling is used by the MED selector
- `cand1` is disabled in AVC mode

### 1.3 Temporal candidate

AVC waveform observation: `reg_tmp_mvp_flag == 0` throughout tested AVC encoding.

Static RTL consequence:

- `neib_c_cu_start = cmdq_cu_start & reg_tmp_mvp_flag`
- Colocated read FSM does not start
- `col_c_avail` is forced unavailable

Therefore the **AVC decoder core does not require colocated-neighbor fetch**.

### 1.4 P8×8 order

Four 8×8 sub-blocks are serial:

`S0 → S1 → S2 → S3`

Later sub-blocks consume reconstructed final MV from earlier sub-blocks through `a_0_reg / b_0_reg` and boundary `buf_reg` logic.

With `reg_tmp_mvp_flag=0`, normal/maximal spatial SRAM transactions are:

| sub-block | A SRAM | B SRAM | Col SRAM | total |
|---|---:|---:|---:|---:|
| S0 / 8_0 | 2 | 2 | 0 | 4 |
| S1 / 8_1 | 0 | 2 | 0 | 2 |
| S2 / 8_2 | 2 | 0 | 0 | 2 |
| S3 / 8_3 | 0 | 0 | 0 | 0 |

Actual A/B reads can be further reduced by availability/boundary conditions.

---

## 2. Encoder RTL evidence table

| Conclusion | RTL evidence |
|---|---|
| Top hierarchy is AMVP + Merge + shared Neighbor | `ve_mvp_top.v:265-358` (`ve_mrg_top`), `360-434` (`ve_amvp_top`), `437-519` (`vc_mvp_get_neib`) |
| `vc_mvp_ctrl` command payload is 14 bit | `vc_mvp_ctrl.v:106-119` |
| AMVP command queue excludes skip | `vc_mvp_ctrl.v:130` |
| Encoder controller traverses active L0 ref indices | `vc_mvp_ctrl.v:408-442` |
| `ve_amvp_top` turns 14-bit command into 17-bit `{blk_sz,cmd}` | `ve_amvp_top.v:197-200` |
| FME result is carried separately into CCU | `ve_amvp_top.v:225-231` |
| Encoder computes `MVD = final_MV - MVP` | `ve_amvp_top.v:258-278` |
| AVC bridge uses blk16 only | `ve_amvp_top.v:351-359`; `ve_mrg_top.v:401-404` |
| A/B request-return alignment uses request-info FIFO | `vc_mvp_rd_mem.v:81-90` |
| blk8 A/B read counts are determined by cux/cuy parity | `vc_mvp_get_neib.v:381-390` |
| Col read is gated by `reg_tmp_mvp_flag` | `vc_mvp_get_neib.v:393-399`, `419-427` |
| SRAM read data is snapshotted into `mvp_neib_*_reg` | `vc_mvp_get_neib.v:1025-1030` and corresponding A block |
| blk8 A mux uses `a_0_reg` on right-half blocks | `vc_mvp_get_neib.v:696-715` |
| blk8 B/C/B2 mux uses `b_0_reg / buf_reg` for lower-row/boundary cases | `vc_mvp_get_neib.v:717-813` |
| `cur_cu_upd` writes reconstructed motion info into rolling regs | `vc_mvp_get_neib.v:993-1015` |
| MED input fields come from command availability | `vc_mvp_cand_gen.v:203-210` |
| MED candidate output is candidate-0 | `vc_mvp_cand_gen.v:329-341` |
| signed component-wise AVC median | `vc_mvp_cand_gen.v:402-445` |
| AVC selection goes to MED and disables candidate-1 | `vc_mvp_cand_gen.v:1214-1220`, `1329` |
| ref/POC matching belongs to general AMVP priority logic | `vc_mvp_cand_prior.v:76-100` |
| temporal priority/scaling is gated by `reg_tmp_mvp_flag` | `vc_mvp_cand_prior.v:110-121` |

---

## 3. Proposed decoder module architecture

![Overall architecture](fig1_avc_decoder_mvp_arch.svg)

### 3.1 `DEC_CTRL` — new decoder scheduler

Purpose: replace encoder-only scheduling behavior of `vc_mvp_ctrl` without changing the proven encoder controller.

Inputs:

- decoder transaction valid
- `part_mode`: P16×16 / P8×8
- `sub_idx` for P8×8
- `cux/cuy`
- A/B availability from CCU/NMU
- `ref_idx_l0`
- signed `mvd_x/mvd_y`
- `is_skip`

Responsibilities:

1. accept one decoded partition transaction only when local transaction storage is available;
2. form the same spatial command context consumed by Neighbor/Candidate logic;
3. P16: one transaction;
4. P8: enforce `S0→S1→S2→S3` ordering;
5. start neighbor fetch;
6. wait for `neib_done` before starting MED candidate generation;
7. **do not** traverse reference indices;
8. hold syntax payload until final-MV result is committed downstream.

Recommended internal command representation:

`{blk_sz[2:0], term, skip, zmv, a_avail[1:0], b_avail[2:0], cuy[2:0], cux[2:0]}`

The lower 14 bits intentionally match encoder `cu_cmd_out`; decoder-only `MVD/ref_idx/sub_idx` remain a separate payload and should not be packed into that legacy command.

### 3.2 `vc_mvp_get_neib` — reuse spatial Neighbor Manager

Reuse:

- A/B `vc_mvp_rd_mem`
- request/gnt/rd_lat alignment
- `mvp_neib_a_reg / mvp_neib_b_reg` snapshot registers
- `a_0_reg / b_0_reg` rolling registers
- `buf_reg` boundary/corner special handling
- `get_rd_neib_a/b()` and `get_neib_a/b()` mapping rules

AVC decode policy:

- `reg_tmp_mvp_flag = 0`
- colocated path stays idle
- RefList data is not consumed by the MED datapath; first implementation may leave the existing RefList engine structurally present to minimize RTL disturbance, then optionally gate it in a later cleanup task

### 3.3 `vc_mvp_cand_gen` — reuse only AVC MED behavior

Recommended first implementation: reuse the existing module with `AMVP_OR_MRG=1`, `reg_avc_mode=1` and consume only candidate-0 MVP.

This intentionally leaves `vc_mvp_cand_prior` and `vc_mvp_scale` instantiated but functionally irrelevant to the AVC MED result. This is safer for the first decoder implementation than extracting/re-writing the median logic immediately.

Decoder-consumed output:

`mvp_x = cand_mv[0][15:0]`

`mvp_y = cand_mv[0][31:16]`

Do not use candidate embedded `ref_idx` as the decoded reference index. The current partition's `ref_idx_l0` comes from the decoded syntax payload and is carried separately.

### 3.4 `DEC_RECON` — new final-MV reconstruction

Inter P16/P8:

`final_mvx = signed(mvp_x) + signed(mvd_x)`

`final_mvy = signed(mvp_y) + signed(mvd_y)`

P_SKIP:

- obtain the same blk16 MED predictor;
- apply project zero-motion rule equivalent to encoder `ve_amvp_top.v:357-359`;
- no FME, no decoded MVD;
- output `0` or median MVP directly as final MV.

![Mode derivation](fig3_mode_mv_derivation.svg)

### 3.5 Decoder result boundary

The MVP decoder core outputs a reconstructed motion transaction:

- final MVX/MVY
- parsed `ref_idx_l0`
- block size / position / sub-index
- skip/inter mode

The exact binding to CCU's decoder-side ports is intentionally a wrapper-level contract. The architectural requirement is:

- result must remain stable until downstream accepts it;
- CCU uses the accepted final MV to issue MC;
- CCU then emits `cur_cu_upd` commit with the same reconstructed motion information.

This keeps the existing ownership model: **CCU owns MC scheduling and `cur_cu_upd`; MVP owns predictor/reconstruction.**

---

## 4. P8×8 neighbor/data-flow detail

![P8 sequence](fig2_p8_serial_neighbor_flow.svg)

### 4.1 Source-class mapping

| sub-block | A | B | C (spatial) | B2 fallback |
|---|---|---|---|---|
| S0 | SRAM snapshot | SRAM snapshot | SRAM snapshot | SRAM snapshot / boundary rule |
| S1 | `a_0_reg` from S0 | SRAM snapshot | SRAM snapshot | SRAM snapshot / boundary rule |
| S2 | SRAM snapshot | `b_0_reg` from S0 | `b_0_reg` from S1 | `buf_reg` / rolling special case |
| S3 | `a_0_reg` from S2 | `b_0_reg` from S1 | rolling/boundary case | rolling/boundary case |

Exact index selection remains the existing `get_neib_a()` / `get_neib_b()` RTL; decoder must **reuse the function behavior rather than re-derive it from a simplified geometry table**.

### 4.2 Commit dependency

`cur_cu_upd` is not a ready/valid transaction. It is a commit pulse carrying stable reconstructed motion information.

For P8, later sub-block candidate generation must not begin before the required prior sub-block commit has updated `a_0_reg/b_0_reg`.

---

## 5. Motion-neighbor persistence loop

The reconstructed final MV participates in three storage horizons:

1. **intra-current-CU rolling state**: `a_0_reg/b_0_reg` in `vc_mvp_get_neib`;
2. **same-CTU NMU buffers**: immediate `cur_cu_upd` update in upstream NMU;
3. **cross-row MVB SRAM persistence**: upstream row buffer accumulates CU updates and DMA-writes MVB at row/CTU boundary.

Decoder MVP must not directly implement MVB write arbitration. It only needs to ensure the final reconstructed motion is returned so CCU can issue the established `cur_cu_upd` commit.

---

## 6. Encoder-only logic explicitly excluded from AVC decoder core

- FME/IME motion search
- FME SATD/min-position logic
- encoder `MVD = final_MV - MVP`
- `vc_mvp_ctrl` reference-index traversal
- HEVC candidate-0/candidate-1 cost selection
- AVC `avc_mvp_push → ve_mrg_top → MC cost` encoder mode-decision path
- Merge RDO/cost comparison
- colocated temporal candidate
- temporal/spatial MV scaling for AVC MED

`ve_mrg_top` remains encoder-side logic. P_SKIP decoder reconstruction is performed directly from the MED predictor and zero-motion rule; it does not need the encoder Merge-cost subsystem.

---

## 7. Reuse / modify / new matrix

| RTL block | Decoder action | Reason |
|---|---|---|
| `ve_mvp_top` | integration change only | route `codec_mode`, selected control, neighbor/result boundary |
| `ve_amvp_top` | keep encoder path untouched | contains FME FIFO, MVD-cost and encoder queues |
| `vc_mvp_ctrl` | **do not reuse as decoder scheduler** | skip filter + ref traversal are encoder behavior |
| new `DEC_CTRL` | **new** | parsed syntax drives one exact partition transaction |
| `vc_mvp_get_neib` | **reuse** | spatial fetch/snapshot/rolling behavior is required |
| `vc_mvp_rd_mem` A/B | **reuse** | proven SRAM request-return alignment |
| Col `vc_mvp_rd_mem` | dormant | AVC tested with `reg_tmp_mvp_flag=0` |
| RefList `vc_mvp_rd_mem` | not consumed by MED | leave structurally present first; optional later gate |
| `vc_mvp_cand_gen` | **reuse MED branch** | bit-exact predictor source |
| `vc_mvp_cand_prior` | present but bypassed for MED | ref matching/scaling not used by AVC MED selector |
| `vc_mvp_scale` | present but bypassed | AVC MED does not use it |
| new `DEC_RECON` | **new** | `MVP+MVD` / P_SKIP final MV |
| `ve_mrg_top` | bypass decoder | encoder skip/inter RDO cost path only |
| `sht_mdl` | optional reuse | input/result elasticity if explicit FIFO is selected |

---

## 8. Control sequence

### 8.1 P16×16 Inter

1. CCU/parser presents decoded P16 transaction.
2. `DEC_CTRL` accepts and latches MVD/ref_idx/context.
3. Start A/B Neighbor fetch.
4. Wait `neib_done`.
5. Start AVC MED candidate generation.
6. Obtain MVP.
7. `DEC_RECON`: `final_MV = MVP + MVD`.
8. Return final-MV transaction to CCU.
9. CCU issues MC and `cur_cu_upd` commit.

### 8.2 P8×8 Inter

Repeat the P16 flow once per `S0/S1/S2/S3`, but enforce serial ordering and wait for the prior sub-block's `cur_cu_upd` dependency before starting a sub-block that consumes its rolling neighbor.

### 8.3 P_SKIP

1. accept skip transaction;
2. use blk16 spatial Neighbor View;
3. generate MED;
4. apply zero-motion special rule;
5. return final skip MV directly; no MVD reconstruction and no FME.

---

## 9. Luna implementation task boundaries

The following split is ready to be converted into strict Codex task packets after interface names are frozen:

| Task | Scope | Main files |
|---|---|---|
| T00 | decoder top-level transaction contract / `codec_mode` routing | MVP top wrapper only |
| T01 | `DEC_CTRL`: P16 command + input rendezvous | new decoder control file |
| T02 | shared Neighbor integration for decoder; Col disabled | top + `vc_mvp_get_neib` wiring only |
| T03 | MED reuse path and decoder MVP extraction | decoder top + `vc_mvp_cand_gen` interface |
| T04 | signed `MVP+MVD` reconstruction | new reconstruction block |
| T05 | P_SKIP zero-motion + MED reconstruction | decoder reconstruction/control |
| T06 | P8 `S0→S3` scheduler and dependency checks | decoder control |
| T07 | `cur_cu_upd` rolling-neighbor closure | decoder/top integration + existing get_neib ports |
| T08 | result holding/backpressure and CCU binding | decoder top / CCU interface |
| T09 | assertions + directed P16/P8/P_SKIP tests | verification only |

Hard rule for Luna: each task may modify only the files explicitly named in that task packet; no architecture redesign and no opportunistic cleanup.

---

## 10. Items not yet frozen

These are intentionally left open rather than guessed:

1. exact decoder result bus binding inside CCU (`existing AMVP-like interface` vs dedicated decoder result channel);
2. exact signed overflow/wrap rule for 16-bit final MV at the implementation boundary;
3. whether first implementation should gate the unused RefList read engine in decoder mode or leave it harmlessly present;
4. exact upstream signal name that converts decoded parser syntax to the proposed decoder transaction.

These four items should be resolved before Luna receives T00/T04/T08, but they do not change the core Neighbor → MED → reconstruction architecture above.
''').strip()+"\n"

(OUT/'AVC_Decoder_MVP_Architecture_Spec_v0.1.md').write_text(spec, encoding='utf-8')

# simple index
index=dedent('''
AVC Decoder MVP Architecture Spec v0.1

Files:
- AVC_Decoder_MVP_Architecture_Spec_v0.1.md
- fig1_avc_decoder_mvp_arch.svg / .png
- fig2_p8_serial_neighbor_flow.svg / .png
- fig3_mode_mv_derivation.svg / .png
''').strip()+"\n"
(OUT/'README.txt').write_text(index,encoding='utf-8')
print('generated', OUT)
