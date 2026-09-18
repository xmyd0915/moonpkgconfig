# 验证记录

最近验证：2026-09-18；平台：Windows x64。

工具链：交接所列 MoonBit 官方便携安装，`moon 0.1.20260915 (2e1a46d 2026-09-15)`。

通过 `scripts/verify.ps1` 执行：

| 检查 | 结果 |
| --- | --- |
| `moon fmt` | 成功 |
| `moon check --target all --deny-warn` | 四目标成功，无警告 |
| `moon test --target all --deny-warn` | wasm 46/46，wasm-gc 46/46，JS 46/46，native 46/46 |
| `moon run cmd/demo` | 成功，输出六项字段及来源，无解析诊断 |
| `moon run --target native cmd/inspect examples/imagekit.pc` | 成功，从磁盘读取并输出九项字段及来源，无解析诊断 |
| `moon run --target native cmd/inspect examples/imagekit.pc --json` | 成功，输出完整条目与空诊断数组 |
| `moon run --target native cmd/inspect examples/broken.pc` | 按预期报告五项问题并返回退出码 1 |

46 个逻辑测试在四个目标各运行一次，不将它们宣传为 184 个独立测试。覆盖顺序变量展开、未定义/自引用、字面美元符、命名空间与大小写、重复/保留定义、BOM/CRLF/注释/续行/Unicode、包元数据校验、直接与传递依赖检查、私有依赖、虚拟包提供者、循环和包冲突诊断、参数聚合与来源、JSON 输出、参数引号/转义、版本分段比较、六种约束运算符及错误恢复、展开大小上限。

当前证据仅证明所覆盖子集。文件入口目前只接收单个 UTF-8 文件，尚未完成目录搜索、系统路径处理和 pkgconf 差异测试，也未确认赛事群中的未公开选题。

## 后续对照工具准备

已查询官方 pkgconf 发行 API：<https://api.github.com/repos/pkgconf/pkgconf/releases/latest>，当前为 pkgconf-3.0.7。后续可使用官方 Windows x64 MSI，发布资产 SHA-256 为 `7a316dba4a4498ea952b746c82deed41c597657095a0f776b75654191b45ae44`。本里程碑未下载安装或运行，不把它计入通过验证。

后续开发保持可追踪的提交记录。月度资格审核和最终验收由主办方决定。
