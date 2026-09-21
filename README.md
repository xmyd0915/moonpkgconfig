# MoonPkgConfig

[![CI](https://github.com/xmyd0915/moonpkgconfig/actions/workflows/ci.yml/badge.svg)](https://github.com/xmyd0915/moonpkgconfig/actions/workflows/ci.yml)

用 MoonBit 读取、检查和解释 C 库的 `pkg-config` 元数据（`.pc` 文件）。

面向原生 FFI 和构建工具开发者：查看编译参数从哪个字段与变量产生，定位未定义变量、重复字段和错误依赖表达式。核心库为纯 MoonBit，读取与求值不调用外部 `pkg-config`。

## 当前状态

开发中，尚未发布到 MoonCakes。`local/moonpkgconfig` 仅供本地导入；公开发布前由维护者确认实际命名空间。

已实现：变量与字段解析、来源位置、错误恢复、元数据校验、版本约束、传递和私有依赖、循环与冲突诊断、虚拟包提供者、编译/链接参数聚合、JSON 输出、单文件检查及整目录检查命令。

下一阶段：扩大真实文件样本、增加参数兼容策略并完善发布准备。当前仍不能替代完整的 `pkg-config`/`pkgconf`。

## 快速运行

需要 MoonBit 工具链。本地开发版本为 `moon 0.1.20260915`。

```sh
moon check --target all
moon test --target all
moon run cmd/demo
moon run --target native cmd/inspect examples/valid/imagekit.pc
moon run --target native cmd/inspect examples/valid/imagekit.pc --json
moon run --target native cmd/inspect examples/invalid/broken.pc
moon run --target native cmd/check examples/valid
moon run --target native cmd/check examples/invalid
moon run --target native cmd/query examples/valid imagekit --cflags --explain
moon run --target native cmd/query examples/valid imagekit --libs
moon run --target native cmd/query examples/valid imagekit --libs --dedupe-paths
moon run --target native cmd/query examples/valid imagekit --libs --static
```

演示输出示例：

```text
Name: imagekit [imagekit.pc:4]
Version: 1.2.0 [imagekit.pc:6]
Libs: -L/opt/example/lib -limagekit [imagekit.pc:9]
Cflags: -I/opt/example/include -DIMAGEKIT=1 [imagekit.pc:11]
Requires: codec >= 2.0 [imagekit.pc:7]
Requires.private: compression >= 1.0 [imagekit.pc:8]
```

Windows 当前工作区可运行 `./scripts/verify.ps1`。它只为本次进程设置便携工具链环境；也可通过 `-MoonHome` 指定其他安装位置。

GitHub Actions 会在全新的 Ubuntu 环境重新下载依赖，执行格式检查、四目标类型检查与测试，并运行正常和错误文件演示。工作流只需要仓库只读权限。

`testdata/pkgconf-3.0.7` 保存了10个未经修改的官方pkgconf测试文件，固定到上游标签、提交和ISC许可证。CI会把它们作为独立兼容语料检查；这证明所选输入受支持，不代表通过pkgconf完整测试套件。

`cmd/inspect` 读取一个 UTF-8 `.pc` 文件，默认列出常用字段、来源和诊断；加 `--json` 输出完整解析结果。检查通过时退出码为 `0`，发现解析或必填元数据问题时为 `1`，用法或文件读取错误时为 `2`。文件访问使用 MoonBit 官方 `moonbitlang/x`，解析核心仍不直接接触文件系统。

`cmd/query` 从显式目录加载其中的 `.pc` 文件，解析指定根包的依赖图，并通过 `--cflags`、`--libs` 或 `--libs --static` 输出聚合参数。普通文本输出按 POSIX shell 规则引用每个参数，含空格、引号、美元符或空参数时仍保留原有参数边界；跨平台程序应使用 `--json` 读取参数数组。`--dedupe-paths` 会稳定地去除重复 `-I`/`-L` 搜索路径，但保留重复库和其他可能影响链接语义的参数；`--explain` 会逐项显示包、字段和源码位置。它不会隐式读取系统搜索路径或环境变量。

`cmd/check` 检查显式目录里的全部 `.pc` 文件，不要求先知道根包名。它会汇总文本解析、必填元数据、公开和私有依赖、版本、依赖环及冲突诊断；正常目录返回 `0`，发现问题返回 `1`，目录读取或调用错误返回 `2`。

## 库接口

```moonbit
let doc = @pc.parse(
  "prefix=/opt/sdk\nLibs: -L${prefix}/lib -lcodec\n",
  source="codec.pc",
)
let libs = doc.field("Libs")
```

`Entry` 同时返回 `raw`（原始值）、`value`（展开值）、`location`（文件/行/列）。变量按定义顺序展开，非法条目不会进入查询结果；应先检查 `Document.diagnostics`。

`Document::validate_metadata` 检查 `Name`、`Description` 和 `Version`，与保留错误继续解析的文本层分开，便于编辑器展示多个问题。

`split_flags` 返回参数数组，不启动 shell；`parse_requirements` 返回包名、比较运算符和版本文本。`compare_versions` 和 `Requirement::matches` 可用于检查已安装版本是否满足约束。

`PackageSet` 接收已解析文档并检查直接依赖，报告重复包、缺失包和版本不满足。`PackageSet::resolve` 生成依赖优先的传递顺序，按需包含 `Requires.private`，并诊断循环依赖及带版本条件的 `Conflicts`。找不到同名包时，可按加入顺序选择 `Provides` 中无版本或精确版本匹配的虚拟包提供者；范围形式的 `Provides` 仍留待后续兼容工作。

`PackageSet::check_all` 把集合中的每个包作为根节点检查，并默认包含私有依赖；重复出现的同一诊断只报告一次，适合 CI 或目录级检查。

`collect_cflags` 与 `collect_libs` 聚合依赖图中的参数，每个参数保留包名、字段和来源位置。静态链接查询会加入私有依赖与 `Libs.private`。`FlagResult::shell_text` 提供可复制到 POSIX shell 的文本表示；直接集成时应使用 `flags` 数组，避免再次解析展示文本。

`FlagResult::deduplicate_search_paths` 可选择性去除重复的连接式或分离式 `-I`/`-L` 参数，并保留首次出现项的来源。它不会去重 `-l`、宏定义或其他参数。

`Document::json_text` 和 `FlagResult::json_text` 提供紧凑或缩进 JSON，供命令行工具、编辑器与 CI 使用。

项目在公开前已有几天的选题、学习和本地原型探索；2026-09-16 整理为公开仓库，此后的实现与验证通过公开提交持续记录。

## 兼容范围

- 支持 LF、CRLF、UTF-8 文本对应的 MoonBit 字符串、开头 BOM、`#` 注释、`\#` 字面量、反斜杠续行。
- 支持 `${name}`、`$${...}` 字面量及调用者提供的 `pcfiledir`。不读取环境变量。
- 重复字段、重复变量、覆盖 `pcfiledir`、未定义引用采用严格错误诊断；不同于某些宽松实现。
- 来源行是逻辑行起始的物理行；列为合并续行并处理注释后的 Unicode 字符列。续行中间的精确物理跨度还未实现。
- 仅解析文本，不查找系统包、不修改构建配置、不运行编译器或安装依赖。
- 尚不实现 sysroot 重写、Windows 自动重定位、系统路径过滤、完整片段去重或全部 pkgconf 3 扩展；当前仅提供显式的搜索路径去重。

可复制的演示步骤见 [docs/demo.md](docs/demo.md)，独立工具对照见 [docs/pkgconf-comparison.md](docs/pkgconf-comparison.md)，上游兼容样本见 [testdata/pkgconf-3.0.7](testdata/pkgconf-3.0.7)，来源与许可证见 [ORIGINS.md](ORIGINS.md)，开发计划见 [ROADMAP.md](ROADMAP.md)。MIT 许可证全文见 [LICENSE](LICENSE)。
