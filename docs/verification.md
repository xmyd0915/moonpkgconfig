# 验证记录

最近验证：2026-09-18；平台：Windows x64。

工具链：交接所列 MoonBit 官方便携安装，`moon 0.1.20260915 (2e1a46d 2026-09-15)`。

通过 `scripts/verify.ps1` 执行：

| 检查 | 结果 |
| --- | --- |
| `moon fmt` | 成功 |
| `moon check --target all --deny-warn` | 四目标成功，无警告 |
| `moon test --target all --deny-warn` | wasm 48/48，wasm-gc 48/48，JS 48/48，native 48/48 |
| `moon run cmd/demo` | 成功，输出六项字段及来源，无解析诊断 |
| `moon run --target native cmd/inspect examples/valid/imagekit.pc` | 成功，从磁盘读取并输出九项字段及来源，无解析诊断 |
| `moon run --target native cmd/inspect examples/valid/imagekit.pc --json` | 成功，输出完整条目与空诊断数组 |
| `moon run --target native cmd/inspect examples/invalid/broken.pc` | 按预期报告五项问题并返回退出码 1 |
| `cmd/query` 三种查询 | Cflags、动态 Libs、静态 Libs 均成功并通过精确输出断言 |
| `cmd/query --dedupe-paths` | 重复 `-L` 被稳定去除，其他参数顺序不变，并通过精确输出断言 |
| `cmd/check examples/valid` | 成功，检查 3 个包、0 项诊断，退出码 0 |
| `cmd/check examples/invalid` | 报告解析及公开/私有依赖问题，共 4 项诊断，退出码 1 |
| GitHub Actions CI | Ubuntu 全新环境成功，运行记录 [35305828387](https://github.com/xmyd0915/moonpkgconfig/actions/runs/35305828387) |

48 个逻辑测试在四个目标各运行一次，不将它们宣传为 192 个独立测试。覆盖顺序变量展开、未定义/自引用、字面美元符、命名空间与大小写、重复/保留定义、BOM/CRLF/注释/续行/Unicode、包元数据校验、直接与传递依赖检查、全包检查去重、私有依赖、虚拟包提供者、循环和包冲突诊断、参数聚合与来源、搜索路径去重、JSON 输出、参数引号/转义、版本分段比较、六种约束运算符及错误恢复、展开大小上限。

当前证据仅证明所覆盖子集。目录查询只读取调用者明确指定的位置，尚未实现系统搜索路径和 sysroot 处理；pkgconf 对照目前也只覆盖仓库中的自编样例。

## 对照工具与记录

已下载并校验官方 pkgconf 3.0.7 Windows x64 MSI，发布资产 SHA-256 为 `7a316dba4a4498ea952b746c82deed41c597657095a0f776b75654191b45ae44`。对照结果和已知差异见 `docs/pkgconf-comparison.md`。

后续开发保持可追踪的提交记录。月度资格审核和最终验收由主办方决定。
