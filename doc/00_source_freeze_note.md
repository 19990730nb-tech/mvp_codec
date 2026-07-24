| 项目     | 内容                                     |
| ------ | -------------------------------------- |
| 原始文件列表 | 12 个 `.v` 文件                           |
| 当前工程性质 | encoder-side MVP RTL                   |
| 已知裁剪   | AMVP 32x32 被裁剪，Merge 仍保留 32x32         |
| 已知混合   | HEVC-like AMVP/Merge + AVC median path |
| 改造原则   | 不直接改原始 RTL，先复制后重构                      |
