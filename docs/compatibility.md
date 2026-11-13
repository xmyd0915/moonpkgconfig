# 真实语料与输入边界验证

本检查验证纯元数据查询和原生命令行边界。固定的上游模板不改写，配置副本、随机种子和结果报告可供复核；真实安装、编译和运行证据另见 zlib/libpng 示例。

## 真实模板与独立预期

`testdata/real-world/corpus.json` 固定 zlib 1.3.1、libffi 3.4.6、libuv 1.48.0、libpng 1.6.59、PCRE2 10.44、Expat 2.6.2 的提交、路径、模板和许可证 SHA-256。检查先校验原始字节，再用清单中的明确值替换构建系统标记。没有安装这些库，也不将配置副本描述为安装产物。

六个包各检查20项查询，共120项：普通/静态编译和链接参数及五种分类共14项，另有版本、变量、变量覆盖、存在性和成功/失败版本条件6项。预期参数、所属包和字段来自人工声明的配置清单；参数位置必须指回对应源文件的声明字段。

全部查询同时与固定的 pkgconf 3.0.7 比较参数数组或文本及退出码。参考工具的 `PKG_CONFIG_*`、`PKGCONF_*` 环境先清除，搜索目录和系统路径过滤显式指定，避免宿主安装和环境选项影响结果。参数对照使用 Python `shlex` 解析展示文本，保留顺序和参数内容，不把引号写法不同误报为参数不同。

另外4项自编两包图验证普通/静态编译查询和分类顺序。静态查询先聚合所有包的 `Cflags`，再按同一包顺序追加 `Cflags.private`；公开和私有依赖都参与。该规则由固定 pkgconf 命令和其 `libpkgconf/pkg.c` 核对。主分支的基础差分由38项扩展为50项，加入共享依赖顺序、私有谓词和 sysroot 场景；连同120项模板查询及4项静态顺序，共覆盖174项参考工具对照。实际通过数由脚本与对应提交 CI 记录。

## 固定种子的输入检查

默认种子为 `20261017`，包含两类检查：

- 64个有效参数输入：组合空参数、空格、单/双引号、反斜杠、美元符、反引号、Unicode 等内容，以 Python `shlex` 为独立预期；再检查 JSON 数组与 shell 展示的参数边界。文件变体覆盖 CRLF、BOM 和无末尾换行。
- 94个截断、语法或随机输入：六份配置模板各3个截断点、12个针对性错误、64个随机文本。分别运行文件检查、静态编译查询和静态链接查询，要求20秒内退出、返回可解析 JSON、保留有效来源位置，且退出码与诊断一致。抽样重复查询检查确定性。

这158个生成输入用于有限的回归和健壮性检查，不构成完整模糊测试或所有错误语义的证明。任意文本输入只检查上述行为约束，不要求与 pkgconf 的宽松解析策略一致。四目标核心单元测试另外保护私有编译字段、错误定位和来源边界。

## 复现与证据

在仓库根目录，使用固定的 MoonBit 工具链、Python 3.9+ 和 pkgconf 3.0.7：

```sh
python scripts/verify-compatibility.py --reference /path/to/pkgconf
python scripts/verify-compatibility.py --seed 20261017 --random-cases 64
```

`PKGCONF` 可指定参考工具；Windows 默认查找忽略目录中的既有固定发行版。没有参考工具时可用 `--no-reference` 单独执行声明预期与输入检查，该模式会明确记录零项 pkgconf 对照，不能作为差分通过的证据。

每次运行保留 `.tmp/compatibility-*` 中的配置文件和生成输入，报告写入 `_build/verification/compatibility.json`，包含工具链、来源与哈希、种子、每项输入和预期、实际通过数量及失败位置。子进程异常或超时使整个检查失败，不跳过失败项。

Windows 完整验证与 Ubuntu CI 均执行此检查。CI 上传 `ubuntu-compatibility` 报告；失败时另上传输入目录，便于重现。

## 实际安装语料与静态链接

`scripts/verify-system-packages.py` 扫描调用方明确指定的实际安装目录，以固定 pkgconf 3.0.7 比较参数集合、退出码、版本和谓词，并检查链接参数的依赖者优先顺序。支持范围是 Ubuntu GNU 用户空间；报告记录真实 `.pc` 文件 SHA-256、目录、系统及参考工具版本。它不要求所有重复参数或无依赖关系的并列包顺序完全一致。

```sh
python scripts/verify-system-packages.py --reference /path/to/pkgconf --directory /path/to/pkgconfig --directory /path/to/extra/pkgconfig
```

`--package` 可限定查询根；`--cli` 可传入已构建的 CLI，否则脚本构建当前源码。默认报告为 `_build/verification/system-packages.json`。语料来自运行环境，数量不能替代固定模板对照，也不能推广为全部系统包兼容。

`python scripts/verify-link-order.py --reference /path/to/pkgconf` 用实际静态库检查三角与跨层共享依赖的链接顺序，需要 pkgconf 3.0.7、GNU 兼容的 C 编译器和 `ar`，用于 Ubuntu 或 Windows MinGW 环境；报告为 `_build/verification/link-order.json`。这些检查补充元数据层断言，实际结果以报告及对应提交的 CI 为准。

## 本次修复及边界

Expat 模板中的 `Cflags.private: -DXML_STATIC` 暴露了静态编译查询缺口。0.3.0新增 `collect_cflags(root, static_linking=true)` 和 `--cflags --static`、静态编译分类查询；默认查询保持原行为，新增结果继续保留包、字段与源码位置。该接口从0.3.0起提供。

`Cflags.private` 是 pkgconf 扩展。当前仍不处理 `Cflags.shared`、完整片段去重、Windows 自动重定位或全部 pkgconf 扩展。模板配置不覆盖每个操作系统、构建开关与可选依赖；库的真实 ABI 和链接正确性需要集成测试验证。

主分支的链接聚合使用迭代逆后序，使依赖者位于被依赖库之前；Cflags 保持原有广度优先顺序。四种谓词检查私有依赖，`--modversion` 不检查私有依赖。加载层默认 `pc_sysrootdir` 为空，CLI 的显式 sysroot 提供展开值，已有 sysroot 前缀不重复添加。这些修复尚未随 MoonCakes 0.3.1 发布。

字段名称仍区分大小写，未知扩展字段不会单独触发诊断；依赖环严格返回 `PC017`，根查询只接受一个包标识符。单值展开上限为1 Mi UTF-16 code units、每文档累计上限为16 Mi，超限返回 `PC009`；该预算不承诺整个进程的内存上限。单个文件读取/解码失败分别为 `PC019`/`PC020`，搜索目录失败仍是 IO 错误，范围见 [CLI JSON 接口](cli-json.md)。
