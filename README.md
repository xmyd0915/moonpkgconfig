# MoonPkgConfig

[English introduction](README.en.md)

[![CI](https://github.com/xmyd0915/moonpkgconfig/actions/workflows/ci.yml/badge.svg)](https://github.com/xmyd0915/moonpkgconfig/actions/workflows/ci.yml)

用 MoonBit 实现的、保留源码位置的 `pkg-config` 元数据引擎。它不只读取 `.pc` 文件，还能解析依赖图、计算编译与链接参数，并解释每个参数来自哪个包、字段和源码行。

MoonPkgConfig 面向 MoonBit 原生 FFI、构建工具和 CI 集成。核心库为纯 MoonBit；解析与求值不启动 shell，也不调用外部 `pkg-config`。

接入原生库时，构建工具不仅需要最终参数，还需要判断版本是否满足要求、定位出错的依赖文件，并解释参数经过哪条依赖路径而来。MoonPkgConfig 将这些信息作为结构化数据交给调用方，适合需要参数来源和精确诊断的工具集成。

[MoonCakes](https://mooncakes.io/docs/xmyd0915/moonpkgconfig) 是 MoonBit 的模块仓库，本项目在其中的名称为 `xmyd0915/moonpkgconfig`。安装可执行 `moon add xmyd0915/moonpkgconfig`；项目名称为 MoonPkgConfig。下面的命令行演示需要克隆本仓库运行。

0.3.0新增静态编译字段与真实 Expat 接入，完整范围见 [0.3.0发行说明](docs/release-notes-0.3.0.md)。

0.3.1修复损坏依赖被误报为缺包的诊断，返回真正出错的文件和行列，接口与范围见 [发行说明](docs/release-notes-0.3.1.md)。正式上传、标签及新项目安装结果见 [发布记录](https://github.com/xmyd0915/moonpkgconfig/blob/main/docs/release.md)。

当前主分支还包含链接顺序、文件读取与 UTF-8 诊断、条件查询和展开预算等修复，详见 [未发布变更](CHANGELOG.md)。这些修复尚未发布到 MoonCakes，已发布0.3.1及历史标签保持原内容。

## 安装命令行工具

当前主分支提供统一命令 `moonpkgconfig`。安装 MoonBit `0.10.20+65efd5b93` 和原生编译工具后，在克隆的仓库根目录运行：

```sh
git clone https://github.com/xmyd0915/moonpkgconfig.git
cd moonpkgconfig
moon update
moon install ./cmd/moonpkgconfig
```

安装后可离开仓库，在自己的项目中检查或查询元数据：

```sh
moonpkgconfig inspect native/example.pc --json
moonpkgconfig check native --path /path/to/sdk/lib/pkgconfig --json
moonpkgconfig query native example --path /path/to/sdk/lib/pkgconfig --libs --static --explain
```

将路径和包名替换为自己的安装。命令安装到 MoonBit 的可执行目录，该目录需要在 `PATH` 中；也可用 `moon install ./cmd/moonpkgconfig --bin <目录>` 指定位置。`moonpkgconfig --help` 列出入口，各子命令支持 `--help`。

这是从当前源码安装的工具，尚未包含在已发布的 MoonCakes 0.3.1 中。既有 `moon run cmd/inspect`、`cmd/query`、`cmd/check` 入口继续可用。`python scripts/verify-cli.py` 验证隔离安装后在仓库外直接执行，并核对旧入口行为。

也可从成功的 CI 下载 `ubuntu-cli-package` 或 `windows-cli-package`，解压后直接运行，不需安装 MoonBit。包内附源码提交号、工具链信息、校验和和依赖许可证；平台范围、30天保留期及操作步骤见 [独立命令行下载](docs/cli-download.md)。这类附件是按提交生成的试用包。

`inspect`、`query`、`check` 的 `--json` 统一覆盖成功、诊断、读取及用法错误。版本、变量和条件查询也可返回 JSON，参数查询的 `--json --explain` 提供结构化依赖路径。完整字段、退出码和外部程序调用示例见 [CLI JSON 接口](docs/cli-json.md)。

## 接入已有多包工程

[多包原生接入示例](examples/project-integration/README.md) 使用已发布的0.3.1计算依赖参数，通过 MoonBit 的实验性 pre-build 配置钩子接入正常的 `moon build/run/test`。它按库包提供编译、链接配置，保留工程已有的源码、导入和自定义构建设置。

```sh
python scripts/verify-project-integration.py
```

该命令准备固定的 zlib、Expat 安装并在工程副本中验证接入；已有安装可直接指定目录。钩子与固定工具链绑定，配置方法、库包传播规则和实验性限制见示例说明。这是本项目维护的集成案例，不代表第三方采用。

## 用发布包构建文件工具

一个实际用法是构建 MoonBit 文件压缩器：在应用的 `.pc` 中声明 `Requires.private: zlib >= 1.2.13`，由 MoonPkgConfig 从真实安装计算头文件、库路径和链接参数。损坏的间接依赖会显示真实文件和行列；修复后继续构建，生成可对实际文件执行压缩、解压的程序。

[通用原生接入模板](examples/native-consumer/README.md) 固定依赖 MoonCakes 0.3.1，同一个规划器和构建适配器支持文件工具、zlib 检查程序和 Expat XML 程序。在仓库根目录运行：

```sh
python scripts/review-native.py
```

需要 MoonBit `0.10.20+65efd5b93`、Python 3.9+、CMake 3.15+；Linux 还需 C 编译器和 `make`，Windows 需 Visual Studio C++ 工具及 Windows SDK，建议使用 ASCII 构建目录（可含空格，详见运行说明）。该命令自动准备固定版本的静态依赖，在仓库之外运行发布包消费者，检查故障、修复、真实执行与 Python zlib 双向互操作，最后打印文件工具路径和本次耗时。

工具用法、已有安装的复用选项和报告位置见 [完整原生流程](docs/native-walkthrough.md)。这些应用由本项目维护，不代表第三方采用。只体验参数查询时，可直接使用下面的快速体验步骤。

## 项目亮点

| 能力 | 实际用途 |
| --- | --- |
| 可解释的参数查询 | `--explain` 把每个 Cflags/Libs 参数追溯到依赖路径、包、字段、文件与行号 |
| 依赖图检查 | 诊断缺失依赖、版本不满足、循环、冲突和公开/私有依赖问题 |
| 稳定集成接口 | 提供结构化 JSON、明确退出码和不丢参数边界的输出 |
| MoonBit 多目标核心 | 同一组逻辑测试覆盖 wasm、wasm-gc、JavaScript 和 native |

## 快速体验

需要 MoonBit 工具链；复现时使用固定版本 `0.10.20+65efd5b93`。在仓库根目录运行：

```sh
moon update
moon run --target native cmd/query examples/valid imagekit --cflags --explain
moon run --target native cmd/check examples/invalid
```

最后一条命令有意检查错误样本，显示诊断并返回退出码 1。完整测试、原生构建和工具差分命令见后文。

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
moon build --target all
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
moon run --target native cmd/query examples/valid imagekit --cflags-only-I --json
moon run --target native cmd/query examples/valid imagekit --libs-only-l --static
moon run --target native cmd/query examples/search/first demo --path examples/search/second --cflags
moon run --target native cmd/query examples/valid imagekit --modversion
moon run --target native cmd/query examples/valid imagekit --variable=prefix
moon run --target native cmd/query examples/valid imagekit --cflags --define-variable=prefix=/custom
moon run --target native cmd/query examples/path-policy paths --cflags --sysroot=/sdk
moon run --target native cmd/query examples/path-policy paths --libs --system-library-path=/usr/lib
moon run --target native cmd/query examples/provides bar-new --path testdata/pkgconf-3.0.7 --exists
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

Windows 可运行 `./scripts/verify.ps1`。它默认使用用户目录中的 `.moon`，只为本次进程设置工具链环境；也可通过 `-MoonHome` 指定其他安装位置。

`scripts/verify-native-example.sh`（Windows 可用对应的 `.ps1`）先编译一个小型 C 静态库，再让 MoonPkgConfig 从 `moonpkg-demo.pc` 算出编译和链接参数，最后构建并运行 C++ 调用程序。这个闭环需要系统提供 C/C++ 编译器和 `ar`。

[zlib FFI 示例](examples/zlib-ffi) 则使用真实安装的 `zlib.pc`：查询参数后生成 MoonBit 原生构建配置，在 MoonBit 程序中调用 zlib 完成 CRC-32、压缩和解压，并检查损坏输入及缓冲区错误。Linux 或 macOS 可运行 `python3 scripts/verify-zlib-ffi.py --pc-dir /path/to/zlib/lib/pkgconfig`；CI 使用固定版本 zlib 1.3.1 构建并运行这一流程。核心库不依赖 zlib，示例单独构建。

Windows 安装 MoonBit、Python 3.9+、CMake 3.15+、Visual Studio C++ 工具及 Windows SDK 后，可运行 `python scripts/verify-zlib-windows.py`。脚本校验并构建固定 zlib 源码，显式将 `-lz` 映射到 MSVC 静态库，验证原始安装和正确引用空格路径的副本；构建日志保留在忽略的 `.tmp` 中。参数转换位于示例脚本，支持范围见 [zlib 示例说明](examples/zlib-ffi/README.md)。

[独立文件压缩消费者](examples/zlib-consumer) 可单独复制运行，直接导入 MoonCakes 0.2.0 的接口。它读取应用依赖声明和已安装的 `zlib.pc`，先展示缺失依赖与版本不满足的定位，修复后构建可处理实际文件的压缩工具。`python scripts/verify-zlib-consumer.py --pc-dir /path/to/zlib/lib/pkgconfig` 会在仓库之外复制并验证整个流程；Windows 上游 CMake 安装另加 `--msvc-lib z=zlibstatic.lib`。该例由本项目维护，不代表第三方采用。

[libpng FFI 示例](examples/libpng-ffi) 接着验证真实的 `libpng → zlib` 私有依赖：跨安装目录解析参数，区分普通与静态查询，检查缺失依赖，再用完整参数构建 MoonBit 程序完成 PNG 编解码和像素核对。

[Expat FFI 示例](examples/expat-ffi) 从真实静态安装查询 `Cflags.private`，生成包含 `XML_STATIC` 的 MoonBit 编译配置，再解析 XML 并与 Python 独立安装核对结果和错误位置。`python scripts/verify-expat.py` 构建固定版本并验证；Windows MSVC 另用移除/恢复私有字段的负对照确认实际链接影响。

`scripts/compare-pkgconf.sh`（Windows 同样有 `.ps1`）把相同样本分别交给 MoonPkgConfig 和 pkgconf，比较 Cflags、动态/静态 Libs、依赖顺序、路径策略、版本、变量覆盖及版本条件退出码。CI 每次提交都会重新执行，不依赖人工抄录结果。

`python scripts/verify-compatibility.py --reference /path/to/pkgconf` 校验六份真实模板和许可证，生成明确配置的副本，并执行独立预期、固定版本差分及输入边界检查。默认参考版本为 pkgconf 3.0.7；结果保存在 `_build/verification/compatibility.json`，CI 上传可下载的报告。

GitHub Actions 在全新的 Ubuntu 与 Windows 环境重新下载依赖，分别执行四目标类型检查、构建、测试和已发布0.3.1的安装验证。Ubuntu 另检查格式并运行正常和错误文件演示；两个平台均构建真实原生消费者。工作流只需要仓库只读权限。

`testdata/pkgconf-3.0.7` 保存了11个未经修改的官方pkgconf测试文件，固定到上游标签、提交和ISC许可证。CI会把它们作为独立兼容语料检查；这证明所选输入受支持，不代表通过pkgconf完整测试套件。

`cmd/inspect` 读取一个 UTF-8 `.pc` 文件，默认列出常用字段、来源和诊断；加 `--json` 输出完整解析结果。检查通过时退出码为 `0`，发现解析或必填元数据问题时为 `1`，用法或文件读取错误时为 `2`。文件访问使用 MoonBit 官方 `moonbitlang/x`，解析核心仍不直接接触文件系统。

`cmd/query` 从显式目录加载其中的 `.pc` 文件，解析指定根包的依赖图，并通过 `--cflags`、`--libs` 或 `--libs --static` 输出聚合参数。根参数只接受一个包标识符，不解析 `"name >= version"` 表达式。`--modversion` 输出版本，`--variable=...` 读取变量，二者只验证所选根，不遍历依赖；`--define-variable=...` 为查询覆盖变量。`--exists`、三个版本条件和全部参数模式检查公开及私有依赖，动态链接仍只输出公开参数。可重复使用 `--path <directory>` 追加搜索目录；目录按命令行顺序查找，同名包由第一个目录中的文件确定，后续目录仍可补足其他依赖。

成功的普通文本参数输出按 POSIX shell 规则引用每个参数，含空格、引号、美元符或空参数时仍保留原有参数边界；参数查询失败时 stdout 不输出部分参数，诊断、用法和 IO 错误写入 stderr。显式 `--help` 输出到 stdout；`--explain` 是附带来源说明的展示模式。跨平台程序应使用 `--json` 读取参数数组，同时检查退出码和状态，不把 stderr 合并到 JSON 中。JSON schema 仍为1，保留原有参数和诊断内容。

目录中的无关坏文件不会阻止正常包查询。单个 `.pc` 条目读取失败返回该包的 `PC019`，非 UTF-8 文件返回 `PC020`；首个坏文件仍阻止后续同名文件或虚拟提供者覆盖它。不存在或不可访问的搜索目录仍返回 IO 错误和退出码2，指出实际目录。`--dedupe-paths` 稳定地去除重复 `-I`/`-L` 搜索路径，保留重复库和其他可能影响链接语义的参数。`--sysroot=...` 同时提供 `pc_sysrootdir` 展开值并重写绝对的 `-I`、`-L` 和 `-isystem` 路径，已具有该目录前缀的路径不重复添加；未指定时加载层的 `pc_sysrootdir` 默认为空。系统路径过滤仍由 `--system-include-path=...`、`--system-library-path=...` 显式指定。命令不会隐式读取系统环境变量。

`cmd/check` 检查显式目录里的全部 `.pc` 文件，不要求先知道根包名。可重复使用 `--path <directory>`，按目录顺序选择同名包；第一个损坏文件也会保留优先级，不能被后面的有效文件掩盖。它汇总文本解析、必填元数据、公开和私有依赖、版本、依赖环及冲突诊断；正常目录返回 `0`，发现问题返回 `1`，目录读取或调用错误返回 `2`。

`check --json` 输出版本为1的结构化报告，包含目录顺序、扫描条目数、选中包名和带来源位置的诊断。`status` 为 `ok`、`diagnostics`、`io_error` 或 `usage_error`；搜索目录读取或用法失败时计数为 `null`，并提供 `error` 对象。`file_count` 包括被优先目录遮蔽的同名 `.pc` 条目，包名只包含成功加载的选中包。单文件 `PC019`、`PC020` 属于诊断，保留计数并返回1；文本检查失败时诊断及汇总写入 stderr。JSON 保持在 stdout，系统 IO 的补充说明可能出现在 stderr，调用方同时检查退出码。

## 验证快照

发行版本的测试数字描述对应历史源码；主分支新增用例的实际执行结果以 [验证记录](docs/verification.md) 和相应提交的 CI 为准。

| 证据 | 当前结果 |
| --- | --- |
| 自动化测试 | 0.3.1源码89个逻辑测试 × 4 个目标，全部通过；0.3.0发行源码为81项 |
| 全新环境 CI | Ubuntu 与 Windows 分别执行四目标检查、构建、测试和0.3.1注册表安装验证；Ubuntu 另检查格式与 CLI 断言，两个平台均构建并运行真实原生消费者 |
| 上游兼容语料 | 11 个未经修改、固定版本与许可证的 pkgconf 3.0.7 官方测试文件 |
| 真实项目模板 | zlib、libffi、libuv、libpng、PCRE2、Expat 六项目的固定版本模板、提交及许可证哈希；配置副本按独立预期检查参数和来源 |
| 自动差分对照 | 当前脚本覆盖55项基础查询、120项真实模板查询和4项静态编译字段顺序，共179项固定 pkgconf 3.0.7 对照；新增范围及执行结果见对照记录与提交 CI |
| 输入边界 | 固定种子的64个有效参数输入及94个截断/异常输入，检查参数边界、JSON、退出码、来源、确定性及超时 |
| 原生闭环 | 使用查询得到的 Cflags/Libs 编译 C 静态库和 C++ 调用程序，并运行核对结果 |
| 真实 MoonBit FFI | 从 zlib 1.3.1 安装生成的 `.pc` 查询参数，在 Ubuntu 与 Windows MSVC 构建 MoonBit 程序并验证 CRC-32、压缩/解压和错误返回 |
| 真实私有依赖 | libpng 1.6.59 → zlib 1.3.1 跨目录查询、普通/静态参数区分、缺失依赖诊断与 MoonBit PNG 像素往返验证 |
| 大图与边界 | 四种1,000包图、5,000包长链解析/目录检查、缺失依赖图及展开边界；保留耗时和峰值内存记录 |
| 打包消费者 | 从实际发行归档提取源码，独立项目验证参数分类、路径、深图、静态编译字段及损坏依赖原始诊断；0.3.1四目标各6项消费者测试通过 |
| 发布包实际使用 | 独立消费者使用 MoonCakes 0.2.0 计算真实 zlib 构建参数，演示缺失依赖、版本错误及修复，再构建文件压缩工具并检查双向互操作 |
| 0.3.0模板历史验证 | 直接依赖 MoonCakes 0.3.0，在仓库之外以同一规划器和适配代码构建 zlib、Expat 应用，分别验证缺失/版本错误、修复及真实执行 |
| 当前通用接入模板 | 固定依赖 MoonCakes 0.3.1，同一规划器和适配器构建 zlib、Expat、文件压缩工具；总入口核对代码摘要，并生成依赖错误、修复、文件互操作和执行结果报告 |
| 损坏依赖定位 | 0.3.1包含8项新增核心回归与22个文件加载 CLI 场景，原始文件错误不再变成缺包提示，覆盖私有模式、目录优先级、虚拟包和共享失败依赖 |

详细命令、工具版本和兼容边界记录在 [验证记录](docs/verification.md) 与 [pkgconf 对照记录](docs/pkgconf-comparison.md) 中。以上是所覆盖范围的证据，不代表完整兼容 pkgconf。

真实模板的配置、固定种子与报告重现见 [兼容性检查](docs/compatibility.md)。`Cflags.private` 静态编译字段从0.3.0起提供。

大型图测量见 [首次性能记录](docs/performance.md) 和 [查询优化记录](docs/query-performance.md)。0.2.0优化路径解释、虚拟包候选查找和有效子图的目录检查，并修复原生深链解析的进程异常退出；数据注明平台、计时范围和问题图的剩余开销。

完整的查询体验见 [快速体验指南](docs/reviewer-guide.md)；它用一个脚本依次展示来源解释、错误诊断、sysroot 和虚拟依赖范围。

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

`PackageSet` 接收已解析文档并检查直接依赖，报告重复包、缺失包和版本不满足。`PackageSet::resolve` 生成依赖优先的传递顺序，按需包含 `Requires.private`，并诊断循环依赖及带版本条件的 `Conflicts`。找不到同名包时，可按加入顺序选择 `Provides` 虚拟包提供者；六种版本运算符的组合按固定 pkgconf 3.0.7 比较矩阵判断。无版本 `Provides` 不会合成可查询版本，这一边界也与参考实现一致。

`PackageSet::check_all` 把集合中的每个包作为根节点检查，并默认包含私有依赖；重复出现的同一诊断只报告一次，适合 CI 或目录级检查。

`PackageSet::select` 选择并验证一个精确包或虚拟提供者，不遍历依赖，适合读取版本和变量；失败时返回原始诊断数组。核心 `collect_libs` 的公开/私有边选择由 `static_linking` 控制；CLI 另在动态链接查询前验证完整依赖图。

0.2.0在单次操作中复用依赖字段和虚拟包候选索引；有效且不涉及冲突字段的子图可复用目录检查结果。问题根仍执行完整诊断遍历，保持每根的冲突语义和错误顺序。每次公开调用重新建立上下文，添加包或修改文档后的下一次查询不会使用旧缓存。

`collect_cflags` 与 `collect_libs` 聚合依赖图中的参数，每个参数保留包名、字段和来源位置。Cflags 会包含公开与私有依赖需要的编译参数；动态 Libs 只使用公开依赖，静态 Libs 会加入私有依赖与 `Libs.private`。`FlagResult::shell_text` 提供可复制到 POSIX shell 的文本表示；直接集成时应使用 `flags` 数组，避免再次解析展示文本。

主分支的链接参数按依赖者在前的顺序输出，修复直接依赖同时被另一个依赖使用时的静态链接次序；Cflags 保留原有广度优先顺序。调用方修改公开包或文档结构后，缺失 `Version` 或包引用会返回诊断，这些路径不再依赖插入时的有效性假设。

0.3.0的 `collect_cflags(root, static_linking=true)` 在所有普通编译参数之后，按同一包顺序追加 `Cflags.private`，适用于 Expat 的 `-DXML_STATIC` 等静态构建要求。CLI 可使用 `--cflags --static`，两种编译分类也可加 `--static`；默认查询不加入私有字段。0.2.0不提供此选项。

0.2.0新增 `PackageSet::dependency_paths(root, include_private=...)`，一次建立最短路径的前驱索引，返回的 `DependencyPaths::path_to(package_id)` 按需生成独立路径数组。适合解释同一根包的多个参数；已有 `dependency_path` 仍可用于单个目标。索引为调用时的快照，后续添加包时应重新建立。

0.2.0新增 `FlagResult::select(FlagSelection)`，可选 `IncludePaths`、`OtherCflags`、`LibraryPaths`、`Libraries` 或 `OtherLibs`，对应下面五种 CLI 模式。它保留参数顺序、重复库、诊断和来源，分离式选项与操作数成对选择，GNU 链接器分组整体保留在其他链接参数中。

| 分类模式 | 输出内容 |
| --- | --- |
| `--cflags-only-I` | `-I` 头文件搜索参数 |
| `--cflags-only-other` | 其余编译参数，包括宏、`-isystem` 及其路径 |
| `--libs-only-L` | `-L` 库搜索参数 |
| `--libs-only-l` | `-l` 库参数，支持 `--static` 加入私有库 |
| `--libs-only-other` | 其余链接参数，包括 framework、线程选项及 GNU 链接器分组 |

每次查询选择一个模式；分类模式同样支持 `--json`、`--explain`、sysroot、系统目录过滤及搜索路径去重。结果保留 `-I`、`-L`、`-l` 前缀，JSON 中分离式选项与操作数仍为两个数组元素。先完成依赖检查和路径策略，再选择分类；即使选中结果为空，依赖或解析错误仍返回诊断和退出码 1。

`FlagResult::deduplicate_search_paths` 可选择性去除重复的连接式或分离式 `-I`/`-L` 参数，两种写法会按同一路径比较并保留首次出现项的原始形式和来源。分离式参数只与同一包、同一字段中的下一项配对，避免跨来源误判。它不会去重 `-l`、宏定义或其他参数。

`FlagResult::with_sysroot` 重写以 `/` 开头的 `-I`、`-L` 与 `-isystem` 路径；`filter_system_search_paths` 只移除调用者明确给出的精确 `-I`/`-L` 目录。两项转换都保留参数来源，且不依赖宿主环境。

`Document::json_text` 和 `FlagResult::json_text` 提供紧凑或缩进 JSON，供命令行工具、编辑器与 CI 使用。

## 兼容范围

- 支持 LF、CRLF、UTF-8 文本对应的 MoonBit 字符串、开头 BOM、`#` 注释、`\#` 字面量、反斜杠续行。
- 支持 `${name}`、`$${...}` 字面量及调用者提供的 `pcfiledir`。不读取环境变量。
- 重复字段、重复变量、覆盖 `pcfiledir`、未定义引用采用严格错误诊断；不同于某些宽松实现。
- 已知字段名称不区分 ASCII 大小写，原始拼写及位置仍保留；变量名和未知扩展字段区分大小写。未知扩展字段不自动参与标准字段查询，也不单独报错。依赖环严格返回 `PC017`。
- 单个展开值和每份文档累计展开值均最多1 Mi（1,048,576）个 UTF-16 code units；变量覆盖不能绕过预算，首次超限返回 `PC009` 并停止解析该文档。解析器每文档保留前100条诊断，遇到下一条时追加 `PC021` 并停止。展开预算不是文件大小或整个进程的内存上限。
- 来源行是逻辑行起始的物理行；列为合并续行并处理注释后的 Unicode 字符列。续行中间的精确物理跨度还未实现。
- 核心库仅解析和查询元数据，不查找系统包、不修改构建配置、不运行编译器或安装依赖；原生集成示例会显式调用编译器。
- sysroot 与系统目录由调用方显式提供；尚不读取 `PKG_CONFIG_SYSROOT_DIR` 等环境变量，不实现 Windows 自动重定位、完整片段去重或全部 pkgconf 3 扩展。

可复制的演示步骤见 [docs/demo.md](docs/demo.md)，快速体验见 [docs/reviewer-guide.md](docs/reviewer-guide.md)，独立工具对照见 [docs/pkgconf-comparison.md](docs/pkgconf-comparison.md)，0.2.0发行说明见 [docs/release-notes-0.2.0.md](docs/release-notes-0.2.0.md)，发布记录见 [docs/release.md](docs/release.md)，上游兼容样本见 [testdata/pkgconf-3.0.7](testdata/pkgconf-3.0.7)，来源与许可证见 [ORIGINS.md](ORIGINS.md)，开发计划见 [ROADMAP.md](ROADMAP.md)。MIT 许可证全文见 [LICENSE](LICENSE)。
