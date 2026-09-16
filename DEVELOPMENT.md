# 开发说明

核心模块不访问文件系统、不调用 shell，不依赖外部 MoonCakes 包。分层为文档解析、变量展开、参数分词、依赖表达式；后续依赖求值和 CLI 在这些接口上构建。

代码以 `moon fmt` 格式化；提交前运行 `moon check --target all --deny-warn`、`moon test --target all --deny-warn` 和 `moon run cmd/demo`。四目标为 wasm、wasm-gc、js、native。验证证据写入 `docs/verification.md`，失败不能记为通过。

Windows 可运行 `scripts/verify.ps1`，接受可选的 `-MoonHome`；默认使用交接中的官方便携安装。脚本遇到第一个失败立即退出，不修改全局 PATH。

仓库只保留与 MoonPkgConfig 有关的源码、测试和开发记录。提交应说明实际改动，不为数量拆分无意义修改。

后续兼容性测试必须有独立预期值或官方工具依据；不能仅对实现输出生成快照并称之为正确性证明。遇到 pkgconf 与 pkg-config 差异时，记录所选兼容策略。
