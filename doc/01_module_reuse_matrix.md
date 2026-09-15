# 01 module reuse matrix
| 模块                    | 类型                   | Decoder 侧处理          |
| --------------------- | -------------------- | -------------------- |
| `vc_mvp_cand_prior.v` | 算法规则                 | 优先复用                 |
| `vc_mvp_cand_gen.v`   | 候选生成核心               | 可复用，但外层控制要改          |
| `vc_mvp_scale.v`      | MV scaling           | 可复用，上游保证 td 不为 0，decoder 侧无需额外除零保护 |
| `vc_mvp_get_neib.v`   | Neighbor 管理          | 部分复用，启动逻辑要改          |
| `vc_mvp_rd_mem.v`     | Neighbor memory read | 结构可复用，地址和接口要核对       |
| `sht_mdl.v`           | FIFO/shift model     | 可复用                  |
| `vc_mvp_ctrl.v`       | Encoder 调度           | 不建议直接复用              |
| `ve_amvp_top.v`       | AMVP encoder top     | 只参考，不直接复用            |
| `ve_mrg_top.v`        | Merge encoder top    | 只参考，不直接复用            |
| `ve_irpu_expg_bits.v` | MVD bit cost         | Decoder 不需要，删除          |
| `ve_mvp_top.v`        | Encoder MVP top      | 只参考层级，不直接改           |
| `ve_defines.v`        | 宏定义                  | 可参考，需核对依赖,不更改    |
