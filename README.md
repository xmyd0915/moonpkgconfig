# MoonPkgConfig

[![CI](https://github.com/xmyd0915/moonpkgconfig/actions/workflows/ci.yml/badge.svg)](https://github.com/xmyd0915/moonpkgconfig/actions/workflows/ci.yml)

用 MoonBit 实现的、保留源码位置的 `pkg-config` 元数据引擎。它不只读取 `.pc` 文件，还能解析依赖图、计算编译与链接参数，并解释每个参数来自哪个包、字段和源码行。

MoonPkgConfig 面向 MoonBit 原生 FFI、构建工具和 CI 集成。核心库为纯 MoonBit；解析与求值不启动 shell，也不调用外部 `pkg-config`。

这个选题来自维护者较多的 C++ 开发实践：接入原生库时，最终参数通常能查到，但参数为什么出现、经过哪条依赖路径以及错误应回到哪里修改并不直观。MoonPkgConfig 尝试把这层过程变成可检查的数据。

## 项目亮点

| 能力 | 实际用途 |
| --- | --- |
| 可解释的参数查询 | `--explain` 把每个 Cflags/Libs 参数追溯到依赖路径、包、字段、文件与行号 |
| 依赖图检查 | 诊断缺失依赖、版本不满足、循环、冲突和公开/私有依赖问题 |
| 稳定集成接口 | 提供结构化 JSON、明确退出码和不丢参数边界的输出 |
| MoonBit 多目标核心 | 同一组逻辑测试覆盖 wasm、wasm-gc、JavaScript 和 native |

## 验证快照

| 证据 | 当前结果 |
| --- | --- |
| 自动化测试 | 54 个逻辑测试 × 4 个目标，全部通过 |
| 全新环境 CI | Ubuntu 上执行格式检查、四目标检查、测试和 CLI 断言 |
| 上游兼容语料 | 10 个未经修改、固定版本与许可证的 pkgconf 3.0.7 官方测试文件 |
| 真实项目模板 | 固定版本、提交和许可证的 zlib 1.3.1 与 libffi 3.4.6 官方 `.pc.in` 内容 |
| 自动差分对照 | CI 对 16 项参数、顺序、变量和退出码行为逐项比较 MoonPkgConfig 与固定的 pkgconf 3.0.7 |
| 原生闭环 | 使用查询得到的 Cflags/Libs 编译 C 静态库和 C++ 调用程序，并运行核对结果 |

详细命令、工具版本和兼容边界记录在 [验证记录](docs/verification.md) 与 [pkgconf 对照记录](docs/pkgconf-comparison.md) 中。以上是所覆盖范围的证据，不代表完整兼容 pkgconf。

## 一分钟体验

需要 MoonBit 工具链：

```sh
moon update
moon run --target native cmd/query examples/valid imagekit --cflags --explain
moon run --target native cmd/check examples/invalid
moon test --target all --deny-warn
sh scripts/verify-native-example.sh
sh scripts/compare-pkgconf.sh
```

第一条查询会输出可直接使用的参数，并紧接着给出来源：

```text
-I/opt/example/include -DIMAGEKIT=1 -I/opt/example/include/codec -I/opt/example/include/compression
  -I/opt/example/include <- imagekit:Cflags [examples/valid/imagekit.pc:13; via imagekit]
  -DIMAGEKIT=1 <- imagekit:Cflags [examples/valid/imagekit.pc:13; via imagekit]
  -I/opt/example/include/codec <- codec:Cflags [examples/valid/codec.pc:10; via imagekit -> codec]
  -I/opt/example/include/compression <- compression:Cflags [examples/valid/compression.pc:10; via imagekit -> compression]
```

## 更多运行方式

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
moon run --target native cmd/query examples/search/first demo --path examples/search/second --cflags
moon run --target native cmd/query examples/valid imagekit --modversion
moon run --target native cmd/query examples/valid imagekit --variable=prefix
moon run --target native cmd/query examples/valid imagekit --cflags --define-variable=prefix=/custom
moon run --target native cmd/query examples/valid imagekit --exists
moon run --target native cmd/query examples/valid imagekit --atleast-version=1.1
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

`scripts/verify-native-example.sh`（Windows 可用对应的 `.ps1`）先编译一个小型 C 静态库，再让 MoonPkgConfig 从 `moonpkg-demo.pc` 算出编译和链接参数，最后构建并运行 C++ 调用程序。这个闭环需要系统提供 C/C++ 编译器和 `ar`。

`scripts/compare-pkgconf.sh`（Windows 同样有 `.ps1`）把相同样本分别交给 MoonPkgConfig 和 pkgconf，比较 Cflags、动态/静态 Libs、依赖顺序、版本、变量覆盖及版本条件退出码。CI 每次提交都会重新执行，不依赖人工抄录结果。

GitHub Actions 会在全新的 Ubuntu 环境重新下载依赖，执行格式检查、四目标类型检查与测试，并运行正常和错误文件演示。工作流只需要仓库只读权限。

`testdata/pkgconf-3.0.7` 保存了10个未经修改的官方pkgconf测试文件，固定到上游标签、提交和ISC许可证。CI会把它们作为独立兼容语料检查；这证明所选输入受支持，不代表通过pkgconf完整测试套件。

`cmd/inspect` 读取一个 UTF-8 `.pc` 文件，默认列出常用字段、来源和诊断；加 `--json` 输出完整解析结果。检查通过时退出码为 `0`，发现解析或必填元数据问题时为 `1`，用法或文件读取错误时为 `2`。文件访问使用 MoonBit 官方 `moonbitlang/x`，解析核心仍不直接接触文件系统。

`cmd/query` 从显式目录加载其中的 `.pc` 文件，解析指定根包的依赖图，并通过 `--cflags`、`--libs` 或 `--libs --static` 输出聚合参数。`--modversion` 输出版本，`--variable=...` 读取变量，`--define-variable=...` 为查询覆盖变量；`--exists` 只用退出码表示包及其依赖是否可用，版本条件选项执行对应检查。可重复使用 `--path <directory>` 追加搜索目录；目录按命令行顺序查找，同名包由第一个目录中的文件确定，后续目录仍可补足其他依赖。普通文本输出按 POSIX shell 规则引用每个参数，含空格、引号、美元符或空参数时仍保留原有参数边界；跨平台程序应使用 `--json` 读取参数数组。JSON 模式在成功和诊断失败时都返回相同的 `flags`、`diagnostics` 对象结构，调用者再根据退出码区分结果。目录中的无关坏文件不会阻止正常包查询，目标包自身或所需依赖有问题时仍返回诊断。`--dedupe-paths` 会稳定地去除重复 `-I`/`-L` 搜索路径，但保留重复库和其他可能影响链接语义的参数；`--explain` 会逐项显示最短依赖路径、包、字段和源码位置。它不会隐式读取系统环境变量。

`cmd/check` 检查显式目录里的全部 `.pc` 文件，不要求先知道根包名。它会汇总文本解析、必填元数据、公开和私有依赖、版本、依赖环及冲突诊断；正常目录返回 `0`，发现问题返回 `1`，目录读取或调用错误返回 `2`。

## 库接口

```moonbit
let doc = @pc.parse(
  "prefix=/opt/sdk\nLibs: -L${prefix}/lib -lcodec\n",
  source="codec.pc",
)
let libs = doc.field("Libs")
```

`Entry` 同时返回 `raw`（原始值）、`value`（展开值）、`location`（字段或变量名的文件/行/列）和 `value_location`（值的起始位置）。变量按定义顺序展开，非法条目不会进入查询结果；应先检查 `Document.diagnostics`。

`Document::validate_metadata` 检查 `Name`、`Description` 和 `Version`，与保留错误继续解析的文本层分开，便于编辑器展示多个问题。

`split_flags` 返回参数数组，不启动 shell；`parse_requirements` 返回包名、比较运算符和版本文本。`compare_versions` 和 `Requirement::matches` 可用于检查已安装版本是否满足约束。

`PackageSet` 接收已解析文档并检查直接依赖，报告重复包、缺失包和版本不满足。`PackageSet::resolve` 生成依赖优先的传递顺序，按需包含 `Requires.private`，并诊断循环依赖及带版本条件的 `Conflicts`。找不到同名包时，可按加入顺序选择 `Provides` 中无版本或精确版本匹配的虚拟包提供者；范围形式的 `Provides` 仍留待后续兼容工作。

`PackageSet::check_all` 把集合中的每个包作为根节点检查，并默认包含私有依赖；重复出现的同一诊断只报告一次，适合 CI 或目录级检查。

`collect_cflags` 与 `collect_libs` 聚合依赖图中的参数，每个参数保留包名、字段和来源位置。Cflags 会包含公开与私有依赖需要的编译参数；动态 Libs 只使用公开依赖，静态 Libs 会加入私有依赖与 `Libs.private`。`FlagResult::shell_text` 提供可复制到 POSIX shell 的文本表示；直接集成时应使用 `flags` 数组，避免再次解析展示文本。

`FlagResult::deduplicate_search_paths` 可选择性去除重复的连接式或分离式 `-I`/`-L` 参数，两种写法会按同一路径比较并保留首次出现项的原始形式和来源。分离式参数只与同一包、同一字段中的下一项配对，避免跨来源误判。它不会去重 `-l`、宏定义或其他参数。

`Document::json_text` 和 `FlagResult::json_text` 提供紧凑或缩进 JSON，供命令行工具、编辑器与 CI 使用。

项目在公开前已有几天的选题、学习和本地原型探索；2026-09-16 整理为公开仓库，此后的实现与验证通过公开提交持续记录。

## 兼容范围

- 支持 LF、CRLF、UTF-8 文本对应的 MoonBit 字符串、开头 BOM、`#` 注释、`\#` 字面量、反斜杠续行。
- 支持 `${name}`、`$${...}` 字面量及调用者提供的 `pcfiledir`。不读取环境变量。
- 重复字段、重复变量、覆盖 `pcfiledir`、未定义引用采用严格错误诊断；不同于某些宽松实现。
- 来源行是逻辑行起始的物理行；列为合并续行并处理注释后的 Unicode 字符列。续行中间的精确物理跨度还未实现。
- 仅解析文本，不查找系统包、不修改构建配置、不运行编译器或安装依赖。
- 尚不实现 sysroot 重写、Windows 自动重定位、系统路径过滤、完整片段去重或全部 pkgconf 3 扩展；当前仅提供显式的搜索路径去重。

可复制的演示步骤见 [docs/demo.md](docs/demo.md)，独立工具对照见 [docs/pkgconf-comparison.md](docs/pkgconf-comparison.md)，发布准备见 [docs/release.md](docs/release.md)，上游兼容样本见 [testdata/pkgconf-3.0.7](testdata/pkgconf-3.0.7)，来源与许可证见 [ORIGINS.md](ORIGINS.md)，开发计划见 [ROADMAP.md](ROADMAP.md)。MIT 许可证全文见 [LICENSE](LICENSE)。
