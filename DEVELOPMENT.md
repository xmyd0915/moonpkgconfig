# 开发说明

核心模块不访问文件系统、不调用 shell。分层为文档解析、变量展开、参数分词、依赖表达式；`cmd/inspect` 使用 `moonbitlang/x/fs` 作为薄文件适配层，不把平台 IO 混入核心接口。

代码以 `moon fmt` 格式化；提交前运行 `moon check --target all --deny-warn`、`moon test --target all --deny-warn` 和 `moon run cmd/demo`。四目标为 wasm、wasm-gc、js、native。验证证据写入 `docs/verification.md`，失败不能记为通过。

CI 固定使用 `0.10.14+7d59c7ec9` 工具链，避免滚动下载改变格式和语言语法。升级工具链时应单独完成迁移和全套验证，再调整固定版本。

Windows 可运行 `scripts/verify.ps1`，接受可选的 `-MoonHome`；默认使用用户目录中的 `.moon` 安装。脚本遇到第一个失败立即退出，不修改全局 PATH。

参数分类的端到端检查为 `python scripts/verify-flag-selection.py`，需要 Python 3；Windows 验证脚本和 Ubuntu CI 均会执行。它检查 JSON 与文本参数边界、来源解释、静态参数及诊断退出码，独立工具对照由 `scripts/compare-pkgconf.*` 执行。

`python scripts/verify-performance.py` 构建原生 release 基准并验证大图及展开边界，不设机器相关的耗时门槛。详细测量使用 `scripts/benchmark.py`，范围、命令和原始记录见 `docs/performance.md`。修改遍历时必须保留深图安全性、最短路径选择以及诊断顺序；批量解释应复用一次 `dependency_paths` 快照。

真实 zlib 和 libpng 的 MoonBit FFI 示例使用独立模块，在 Linux CI 中构建和运行。命令及前置条件见各自示例的 README；它们不加入核心库的四目标依赖。两个运行脚本共用 `scripts/native_ffi.py`，修改共用代码时必须重跑两条集成流程。

仓库只保留与 MoonPkgConfig 有关的源码、测试和开发记录。提交应说明实际改动，不为数量拆分无意义修改。

后续兼容性测试必须有独立预期值或官方工具依据；不能仅对实现输出生成快照并称之为正确性证明。遇到 pkgconf 与 pkg-config 差异时，记录所选兼容策略。
