# 开发说明

核心模块不访问文件系统、不调用 shell。分层为文档解析、变量展开、参数分词、依赖表达式；`cmd/inspect` 使用 `moonbitlang/x/fs` 作为薄文件适配层，不把平台 IO 混入核心接口。

代码以 `moon fmt` 格式化；提交前运行 `moon check --target all --deny-warn`、`moon test --target all --deny-warn` 和 `moon run cmd/demo`。四目标为 wasm、wasm-gc、js、native。验证证据写入 `docs/verification.md`，失败不能记为通过。

CI 固定使用 `0.10.14+7d59c7ec9` 工具链，避免滚动下载改变格式和语言语法。升级工具链时应单独完成迁移和全套验证，再调整固定版本。

Windows 可运行 `scripts/verify.ps1`，接受可选的 `-MoonHome`；默认使用用户目录中的 `.moon` 安装。脚本遇到第一个失败立即退出，不修改全局 PATH。

发行验证使用 `python scripts/verify-install.py --package`：提取实际 ZIP，以独立 `moon.work` 连接归档源码和消费者，执行公开接口测试。默认不传参数时从 MoonCakes 安装当前模块版本，不设置本地依赖覆盖；此模式仅在版本已发布后运行。消费者目录保留在忽略的 `.tmp` 中，便于核对下载内容。

`moon.mod` 当前版本为0.3.1发行候选，尚未发布。发行前运行归档模式，上传成功后运行注册表模式；复验已发布版本需显式指定 `--version 0.3.0` 或 `--version 0.2.0`。0.3.1消费者新增2项诊断映射验证，四目标各运行6项；0.3.0运行原4项，0.2.0运行原3项。归档模式另从提取源码运行22个文件加载场景。可加 `--report <路径>` 保存版本、归档哈希和命令结果；失败报告不会标记为通过。

参数分类的端到端检查为 `python scripts/verify-flag-selection.py`，需要 Python 3；Windows 验证脚本和 Ubuntu CI 均会执行。它检查 JSON 与文本参数边界、来源解释、静态参数及诊断退出码，独立工具对照由 `scripts/compare-pkgconf.*` 执行。

`python scripts/verify-load-diagnostics.py` 构建原生命令，验证22个文件加载场景，报告为 `_build/verification/load-diagnostics.json`。适配层应把 `diagnostics_by_package` 传给当前主分支的可选 `unavailable` 参数；不要解析诊断文本来推断包名，也不要把无关损坏文件加入单包查询。新增参数尚未在0.3.0发布。

`python scripts/verify-performance.py` 构建原生 release 基准并验证大图及展开边界，不设机器相关的耗时门槛。详细测量使用 `scripts/benchmark.py`，范围、命令和原始记录见 `docs/performance.md`。修改遍历时必须保留深图安全性、最短路径选择以及诊断顺序；批量解释应复用一次 `dependency_paths` 快照。

查询期间的提供者索引和依赖步骤放在内部 `QueryContext`，不得跨公开调用复用，因为 `PackageSet` 和文档由调用方持有。目录优化仅复用能够证明无诊断且无冲突字段的子图；问题根保持完整遍历。提供者顺序、精确包优先、文档修改可见性和每根冲突范围由回归测试保护。后续测量及剩余边界见 `docs/query-performance.md`。

真实 zlib 和 libpng 的 MoonBit FFI 示例使用独立模块，在 Linux CI 中构建和运行。zlib 另有 Windows MSVC CI，执行 `python scripts/verify-zlib-windows.py`；本地完整检查可加 `scripts/verify.ps1 -WithWindowsZlib -CMake <路径>`。命令及前置条件见各自示例的 README；它们不加入核心库的四目标依赖。两个运行脚本共用 `scripts/native_ffi.py`，修改共用代码时必须重跑 Linux 的两条集成流程以及 Windows zlib。

`python scripts/test-native-ffi.py` 在 Windows 本地验证及两个 CI 平台执行。MSVC 参数适配仅属于示例脚本：保留 JSON 参数和来源边界，未知选项必须报错，静态库名差异由调用方显式映射。不能把示例成功表述为核心库已实现完整的 Windows 参数转换或自动重定位。

`examples/zlib-consumer` 是自包含的消费项目，固定依赖 MoonCakes 0.2.0。`python scripts/verify-zlib-consumer.py --pc-dir <目录>` 将它复制到仓库之外，检查缺失/版本错误和修复后的文件工具；Windows CMake 安装另传 `--msvc-lib z=zlibstatic.lib`。不要通过 `moon.work` 或本地主分支替换来让该检查通过。Windows zlib 准备脚本加 `--with-consumer` 可复用安装执行此检查；完整验证的 `-WithWindowsZlib` 已包含它。构建程序与演示可使用本地包缓存，但必须是指定的已发布版本。

仓库只保留与 MoonPkgConfig 有关的源码、测试和开发记录。提交应说明实际改动，不为数量拆分无意义修改。

`examples/native-consumer` 固定使用 MoonCakes 0.3.0，规划器和构建适配层可用于不同库。`python scripts/verify-native-consumer.py --library zlib --pc-dir <目录>` 与 `--library expat` 分别在仓库外验证同一模板的失败、修复与真实运行；Windows zlib 另传库名映射。两个准备脚本加 `--with-native-consumer` 可复用固定安装；完整验证的两个可选开关已包含该检查。不要把主分支新增的 `unavailable` 参数加入这个已发布版本消费者。完整串联演示见 `docs/native-walkthrough.md`。

真实 Expat 验证为 `python scripts/verify-expat.py`，构建固定2.6.2静态库后调用 `verify-expat-ffi.py`；Linux 与 Windows CI 均执行。本地可加 `scripts/verify.ps1 -WithExpat -CMake <路径>`，既有 `-WithWindowsZlib` 可同时指定。Windows MSVC 环境发现已放入共用 `native_ffi.py`，修改时必须重跑两种 Windows 库及 Linux 的既有 FFI 集成。Expat 的私有宏必须来自查询结果，不得在 C 包装或构建脚本中补写；负对照要求真实导入符号链接失败。

后续兼容性测试必须有独立预期值或官方工具依据；不能仅对实现输出生成快照并称之为正确性证明。遇到 pkgconf 与 pkg-config 差异时，记录所选兼容策略。

`python scripts/verify-compatibility.py` 校验六个真实上游模板及许可证的固定哈希，执行声明预期、124项 pkgconf 3.0.7 对照与158个固定种子输入。参考工具可由 `--reference` 或 `PKGCONF` 指定；默认种子及重现方法见 `docs/compatibility.md`。Windows 完整流程及 Ubuntu CI 执行该检查，报告保存在 `_build/verification/compatibility.json`。新增语料必须保留完整许可证、固定提交与配置替换值，不得通过刷新预期输出掩盖差异。
