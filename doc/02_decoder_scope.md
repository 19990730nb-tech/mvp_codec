# 02 Decoder MVP Scope

## 1. 目标

本阶段目标是在现有 encoder-side MVP RTL 基础上，规划 decoder-side MVP 模块的第一版实现范围。

第一版 decoder MVP 不追求完整标准 HEVC decoder，而是优先复现当前工程实际支持的 MVP 行为，包括：
- HEVC-like AMVP
- HEVC-like Merge
- AVC mode median MVP
- temporal colocated candidate
- spatial neighbor candidate
- MV scaling

## 2. 支持范围

| 项目 | 第一版 Decoder 是否支持 | 说明 |
|---|---|---|
| P slice / List0 | 支持 | 当前优先只做 L0 单向预测 |
| B slice / List1 / Bi-pred | 暂不支持 | 第一版仅覆盖 P-slice / List0 单向预测，暂不处理 L1 与双向预测
| AMVP blk8 | 支持 | 需要复现现有 RTL 行为 |
| AMVP blk16 | 支持 | 需要复现现有 RTL 行为 |
| AMVP blk32 | 暂不支持 | 当前 encoder AMVP path 已裁剪 32x32 |
| Merge blk8 | 支持 | 复用现有 Merge candidate 逻辑 |
| Merge blk16 | 支持 | 复用现有 Merge candidate 逻辑 |
| Merge blk32 | 支持 | 当前 Merge path 仍保留 32x32 |
| AVC mode | 支持 | 重点支持 median predictor path |
| TMVP / colocated C0/C1 | 支持 | 按现有 col_c / col_c_avail 机制 |
| MV scaling | 支持 | 上层已确认 td 不为 0，无需额外除零保护 |
| NUM_REF=2 | 支持 | 先按当前工程配置 |
| NUM_REF > 2 泛化 | 暂不支持 | 第一版按当前工程 NUM_REF=2；NUM_REF=1/2 逻辑虽有部分参数化痕迹，但不在第一版重新泛化
| Tiles / WPP / 多 slice 复杂边界 | 暂不支持 | 第一版只保证当前工程边界模型 |