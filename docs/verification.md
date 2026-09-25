# 验证记录

最近验证：2026-09-25；平台：Windows x64。

工具链：交接所列 MoonBit 官方便携安装，`moon 0.1.20260915 (2e1a46d 2026-09-15)`。

通过 `scripts/verify.ps1` 执行：

| 检查 | 结果 |
| --- | --- |
| `moon fmt` | 成功 |
| `moon check --target all --deny-warn` | 四目标成功，无警告 |
| `moon test --target all --deny-warn` | wasm 59/59，wasm-gc 59/59，JS 59/59，native 59/59 |
| `moon run cmd/demo` | 成功，输出六项字段及来源，无解析诊断 |
| `moon package --list` | 成功，包含核心源码、README、许可证与来源说明，不包含构建、工具或凭据文件 |
| `moon run --target native cmd/inspect examples/valid/imagekit.pc` | 成功，从磁盘读取并输出九项字段及来源，无解析诊断 |
| `moon run --target native cmd/inspect examples/valid/imagekit.pc --json` | 成功，输出完整条目与空诊断数组 |
| `moon run --target native cmd/inspect examples/invalid/broken.pc` | 按预期报告五项问题并返回退出码 1 |
| `cmd/query` 三种查询 | Cflags、动态 Libs、静态 Libs 均成功并通过精确输出断言 |
| `cmd/query --dedupe-paths` | 连接式与分离式重复搜索路径按同一路径稳定去除；孤立选项不会跨包或字段绑定下一参数 |
| `cmd/query` 路径策略 | 显式系统目录过滤与 sysroot 重写通过精确输出断言；连接式/分离式参数均保留来源 |
| `cmd/query` 虚拟包范围 | 官方 `provides.pc` 的六种运算符按 pkgconf 3.0.7 比较矩阵解析；匹配与拒绝样例退出码一致 |
| `cmd/query` 参数引用 | 官方 `fragment-quoting.pc` 中含字面引号的宏参数按 POSIX shell 规则输出，并通过精确断言 |
| `cmd/query` 参数顺序 | 菱形依赖中 Cflags 包含公开/私有依赖，动态 Libs 只含公开依赖，静态 Libs 加入私有依赖；顺序与 pkgconf 3.0.7 一致 |
| `cmd/query --explain` | 每个参数显示包、字段、源码位置及从根包出发的最短公开/私有依赖路径 |
| `cmd/query` 查询隔离 | 同目录存在无关损坏文件时正常包仍可查询；直接查询损坏包会返回其原始诊断和退出码 1 |
| `cmd/query --json` 失败结果 | 损坏目标包仍输出可解析的 `flags`、`diagnostics` 对象，诊断为 `PC004`，退出码 1 |
| `cmd/query --path` | 首目录中的同名包获胜，后续目录可补足依赖；反转目录顺序会按预期改变选中版本 |
| `cmd/query` 元数据模式 | 版本输出、存在性、最低/最高/精确版本条件的输出及退出码与 pkgconf 3.0.7 对照一致 |
| `cmd/query` 变量模式 | 变量读取、调用方覆盖及覆盖后的依赖参数展开与 pkgconf 3.0.7 对照一致 |
| `cmd/check examples/valid` | 成功，检查 3 个包、0 项诊断，退出码 0 |
| `cmd/check examples/invalid` | 报告解析及公开/私有依赖问题，共 4 项诊断，退出码 1 |
| `cmd/check testdata/pkgconf-3.0.7` | 11个未经修改的官方pkgconf 3.0.7样本全部通过，退出码 0 |
| 原生 C/C++ 闭环 | 查询 `moonpkg-demo.pc` 得到参数，编译 C 静态库与 C++ 调用程序，运行输出精确匹配 |
| `cmd/check testdata/real-world` | zlib 1.3.1 与 libffi 3.4.6 固定上游模板全部通过，退出码 0 |
| 自动 pkgconf 差分 | 22 项 Cflags、动态/静态 Libs、依赖顺序、路径策略、虚拟包、真实模板、版本、变量覆盖及退出码与固定的 pkgconf 3.0.7 一致；仅忽略行末空白差异 |
| GitHub Actions CI | Ubuntu 全新环境成功，含包内容检查、原生 C/C++ 闭环、11个上游样本及22项固定版本差分，运行记录 [36104374695](https://github.com/xmyd0915/moonpkgconfig/actions/runs/36104374695) |

59 个逻辑测试在四个目标各运行一次，不将它们宣传为 236 个独立测试。覆盖顺序变量展开、调用方变量覆盖、未定义/自引用、字面美元符、命名空间与大小写、重复/保留定义、BOM/CRLF/注释/续行/Unicode、字段和值位置、包元数据校验、直接与传递依赖检查、全包检查去重、最短公开/私有依赖路径、Cflags 私有依赖语义、虚拟包提供者及范围比较矩阵、循环和包冲突诊断、参数聚合与来源、稳定的菱形依赖顺序、POSIX shell 参数边界、跨写法搜索路径去重、系统目录过滤、sysroot重写和来源边界、JSON 输出、参数引号/转义、版本分段比较、六种约束运算符及错误恢复、展开大小上限。

当前证据仅证明所覆盖子集。目录、系统路径和sysroot均由调用者显式指定，不读取宿主pkg-config环境；参数结果对照使用自编依赖图，上游语料验证使用11个固定的pkgconf官方测试文件。

## 对照工具与记录

已下载并校验官方 pkgconf 3.0.7 Windows x64 MSI，发布资产 SHA-256 为 `7a316dba4a4498ea952b746c82deed41c597657095a0f776b75654191b45ae44`。对照结果和已知差异见 `docs/pkgconf-comparison.md`。

后续开发保持可追踪的提交记录。月度资格审核和最终验收由主办方决定。
