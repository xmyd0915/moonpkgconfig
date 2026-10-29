# 从依赖错误到可运行的文件工具

这条流程使用已发布的 `xmyd0915/moonpkgconfig@0.3.1`，从原生依赖的 `.pc` 元数据计算构建参数，定位损坏文件，修复后构建并运行应用。同一个规划器和构建适配器支持 zlib 检查程序、Expat XML 程序，以及可压缩、解压实际文件的命令行工具。

这些应用均由本项目维护，用于展示发布包的集成方式，不代表第三方采用。

## 准备

需要 MoonBit `0.10.16+b1a0e846e`、Python 3.9+、CMake 3.15+，以及原生构建工具：Linux 使用 C 编译器和 `make`；Windows 使用 x64 Visual Studio C++ 工具及 Windows SDK。首次运行需要访问源码下载地址和 MoonCakes。

在仓库根目录运行：

```sh
python scripts/review-native.py
```

Linux 上若 Python 3 的命令名为 `python3`，用它替换上面的 `python`。脚本先检查工具，再下载并校验固定版本的 zlib 1.3.1、Expat 2.6.2 源码，构建静态安装并自动传递目录。构建日志和安装文件保存在忽略的 `.tmp/native-dependencies-*` 下，无须手动查找临时路径。

工具不在 PATH 时，可使用 `--moon /path/to/moon`、`--cmake /path/to/cmake` 指定；POSIX 环境可用 `--cc /path/to/cc`。Windows 自动发现 MSVC，自动准备的 zlib 使用 `z=zlibstatic.lib` 映射。

Windows 自动准备已验证包含空格的 ASCII 工作目录。CMake 3.31.8、NMake 与 MSVC 19.51 的组合在中文工作目录中可能在编译器自检的 PDB 链接阶段失败；使用这套工具时，请把仓库放在 ASCII 路径中。该限制发生在原生库构建工具中，不能据此判断 `.pc` 解析器的字符支持范围。

已有对应版本源码归档时，可以省去源码下载，归档仍会校验 SHA-256：

```sh
python scripts/review-native.py --zlib-archive /path/to/zlib-1.3.1.tar.gz --expat-archive /path/to/expat-2.6.2.tar.gz
```

仅复用已安装的库时，须同时传入两个目录：

```sh
python scripts/review-native.py --zlib-pc-dir /path/to/zlib/lib/pkgconfig --expat-pc-dir /path/to/expat/lib/pkgconfig
```

Windows 的上游 CMake zlib 静态安装另加 `--zlib-msvc-lib z=zlibstatic.lib`；目录含空格时加引号。该模式不执行依赖下载或 CMake 安装。源码归档选项只用于自动准备模式，不能与已有目录混用。可先单独运行 `python scripts/prepare-native.py` 获取工具检查、安装路径和归档摘要报告。

## 流程与结果

1. 将通用模板复制到仓库外，直接安装 MoonCakes 0.3.1，不使用本地模块覆盖。
2. 分别查询 zlib、Expat 应用，验证缺失依赖、版本不满足及损坏依赖。损坏文件中的 `broken=${missing}` 应返回 `PC004`，定位到依赖文件第 1 行第 8 列。
3. 恢复依赖副本后，使用查询得到的参数构建并执行应用。zlib 检查 CRC-32、压缩/解压和错误返回；Expat 使用 `Cflags.private` 中的 `-DXML_STATIC`，分块解析 XML，并与 Python 独立安装核对结果及错误位置。
4. 再用相同规划器和适配器构建文件工具。移除损坏的临时 zlib 覆盖文件后，直接使用真实安装；验证空文件、UTF-8 文本、二进制文件往返，以及与 Python zlib 的双向互操作。
5. 检查损坏输入、已有输出、相同输入输出路径、缺失输入和用法错误的退出结果，并核对安装元数据未被改写。

完成后打印 `Native walkthrough: passed`、本次耗时和文件工具的绝对路径。首次源码下载、依赖编译和缓存状态会影响耗时，实际数值记录在报告的 `elapsed_seconds` 中。

报告保存在 `_build/verification/`：

| 文件 | 内容 |
| --- | --- |
| `native-walkthrough.json` | 总体状态、准备记录、三个消费者报告名称、总耗时和文件工具 `executable` 路径 |
| `native-consumer-zlib.json` | zlib 故障、修复、来源、构建和直接执行结果 |
| `native-consumer-expat.json` | Expat 故障、修复、静态编译参数及 XML 对照结果 |
| `native-file-tool.json` | 真实文件操作、Python 互操作、失败行为、源文件摘要及可执行文件路径 |

总入口还会比较三个消费者的 `template_sha256`，确认它们使用完全相同的 `build.py` 与 `cmd/plan/main.mbt`。本机路径和日志仅存在于生成报告中，报告不纳入源码。跨平台执行结果应以对应 CI 运行及其附件为准。

## 使用生成的文件工具

在完成上述流程后，PowerShell 可直接从报告读取路径：

```powershell
$tool = (Get-Content _build/verification/native-walkthrough.json -Raw | ConvertFrom-Json).executable
& $tool compress README.md _build/verification/README.zlib
& $tool decompress _build/verification/README.zlib _build/verification/README.restored.md
```

Linux：

```sh
tool=$(python3 -c 'import json; print(json.load(open("_build/verification/native-walkthrough.json"))["executable"])')
"$tool" compress README.md _build/verification/README.zlib
"$tool" decompress _build/verification/README.zlib _build/verification/README.restored.md
```

还原文件应与原始 README 内容一致。工具以独占创建方式写入新文件，拒绝已有输出；重复运行时需选择新的输出路径。写入失败时可能留下本次创建的部分文件，工具不会按路径自动删除文件。

它处理的是 zlib 数据流，不是 ZIP 或 gzip；读取过程中限制输入大小，压缩输入上限为 64 MiB，解压输出上限为 64 MiB，压缩数据输入另受对应 zlib 压缩上界限制。压缩和解压仍在内存中完成，适合受控大小的文件操作，不提供流式大文件处理。

## 集成到自己的项目

复制 [通用模板](../examples/native-consumer/README.md)，按其中说明修改 `consumer.json`、应用 `.pc` 与 C/C++ 包装接口。模板适用于单个根目录可执行包，生成副本的构建配置；已有自定义 `moon.pkg` 或 `moon.pkg.json` 会明确报错。较大的构建系统可直接消费规划器 JSON。

使用 0.3.1 API 的适配层应把文件加载器的失败映射传入查询：

```moonbit
let loaded = @loader.load_directories(directories)
let result = loaded.packages.collect_libs(
  root,
  static_linking=true,
  unavailable=loaded.diagnostics_by_package,
)
```

`resolve`、`check_all`、`collect_cflags`、`collect_libs` 及两个依赖路径接口支持这个可选映射。只有当前遍历实际使用的失败依赖会影响查询；目录检查另汇总全部加载错误。同一失败依赖被多个分支引用时原始诊断只返回一次。有效精确包优先；被排除的同名文件阻止虚拟提供者回退。核心仍只接收内存数据，不增加文件系统依赖。此参数从 0.3.1 起提供。
