# 02 Decoder Scope：H.264/AVC 解码

## 1. 目标

`src_encoder_ref/` 是现有的混合视频编码参考。本阶段只在此架构上实现 H.264/AVC decoder 侧的运动信息处理，代码目标目录为 `src_codec_dec/`；当前开发代码位于 `src_codec_dev/`。

H.265 资料仅作为理解现有混合架构的参考，不作为本阶段 decoder 的实现目标。

## 2. 本阶段范围

- H.264/AVC P slice、List0；
- 当前优先支持 P16x16；
- 支持 P8x8（`part_mode=1`）及连续 `sub0` 到 `sub3` 多子块处理；
- 使用 decoder 输入的 `ref_idx`，不进行 encoder-style reference traversal；
- 根据 neighbor 结果生成 AVC MVP，并完成 `MVP + MVD`；
- 将 reconstructed MV 和 `ref_idx` 送往 MC，并完成必要的 neighbor-cache 更新；
- 重点验证 `ref_idx=0` 和 `ref_idx=1` 均能完成：

  `neighbor → candidate → done → controller exit`

decoder 路径不得改变正常工作的 encoder、Merge 及其他无关逻辑。

## 3. 不在本阶段范围内

- H.265/HEVC decoder；
- B slice、List1、双向预测；
- NAL/RBSP、SPS/PPS、slice parser；
- residual、反量化、反变换、deblocking；
- DPB、POC 和 reference-list 管理；
- 未单独确认的其他 AVC partition mode 及更大范围的参数化支持。

## 4. 当前 decoder 边界

上游提供当前块的 partition 信息、`ref_idx`、MVD、skip 等已解析运动信息。当前 RTL 中对应 `ccu2irpu_*` 输入。

decoder MVP 控制只负责：

1. 接收一次 decoder transaction；
2. 读取所需 neighbor；
3. 生成 AVC candidate/MVP；
4. 完成 MV 重建并输出 `ref_idx`；
5. 在 MC transaction 完成后更新 neighbor context；
6. 退出当前 transaction。

reference picture 的具体构建和管理由外部模块负责。

## 5. 最小验收条件

至少覆盖：

| Case | 结果 |
|---|---|
| AVC P16x16，`ref_idx=0` | 正常完成 neighbor、candidate、MV 重建和 controller exit |
| AVC P16x16，`ref_idx=1` | 与 `ref_idx=0` 一样正常退出，不等待其他 reference candidate |
| AVC P8x8，`part_mode=1`，`ref_idx=0/1` | 连续完成 `sub0 → sub1 → sub2 → sub3`，每个子块均完成 neighbor、candidate、MV 重建，并正确进入下一个子块 |

所有 case 均应满足：输入 `ref_idx` 被保留，`MVP + MVD` 结果正确，MC handshake 完成，且不发生 FSM 卡死。
