# 用发布包构建文件压缩工具

这是一个可以单独复制运行的 MoonBit 消费项目。构建工具直接导入 MoonCakes 的 `xmyd0915/moonpkgconfig@0.2.0` 及其文件适配接口，读取项目依赖声明和真实安装的 `zlib.pc`，取得静态编译参数，再构建一个可以压缩、解压文件的原生程序。

`cmd/plan` 使用公开库 API，不调用主仓库的查询命令。`build.py` 负责调用构建工具和编译器；应用程序、查询程序和脚本均在本目录内。复制本目录时不需要主仓库的其他文件，也不使用 `moon.work` 或本地依赖替换。

## 构建与运行

需要 MoonBit `0.10.16+b1a0e846e`、Python 3.9+、C 编译器，以及带静态库、头文件和 `zlib.pc` 的 zlib 开发安装。Linux/macOS 使用 POSIX 编译器；Windows x64 使用 Visual Studio C++ 工具和 Windows SDK，静态库使用 `/MT` 运行库。

在复制后的本目录运行：

```sh
python build.py --pc-dir /path/to/zlib/lib/pkgconfig
```

Windows 上游 CMake 安装可运行：

```powershell
python build.py --pc-dir C:/libraries/zlib/share/pkgconfig --msvc-lib z=zlibstatic.lib
```

`--path` 可追加依赖搜索目录，`--moon`、`--cc` 可指定工具。Windows 的 `-lNAME` 默认转换为 `NAME.lib`；上游 zlib 静态库实际名为 `zlibstatic.lib`，因此需要显式映射。适配器仅接受有限的 `-I/-D/-U/-L/-l` 参数，未知选项会报错。含空格的 `.pc` 路径值必须正确引用。

脚本打印 zlib 版本、`compression-app -> zlib` 私有依赖路径、每个参数的文件与行号，以及最后的 `Executable` 路径。使用该路径处理自己的文件：

```text
<Executable> compress input.txt output.zlib
<Executable> decompress output.zlib restored.txt
```

输出是标准 zlib 数据流，不是 gzip 或 ZIP。程序支持最多 64 MiB 的未压缩内容，拒绝已有输出文件；输入会整体读入内存，解压按有上限的缓冲区增长。它是小型文件工具，不提供流式处理、目录压缩或归档管理。

构建产物、依赖故障副本和机器可读记录保留在本目录的 `_build/consumer-*` 中。原始源码、项目依赖文件和已安装的 `zlib.pc` 不会被改写。

## 重现一次依赖故障与修复

在上述构建命令后加 `--demo`：

```sh
python build.py --pc-dir /path/to/zlib/lib/pkgconfig --demo
```

程序依次执行：

1. 只加载项目的 `compression-app.pc`，不提供 zlib 搜索目录：返回 `PC015`，指出第 4 行缺少 zlib。
2. 在独立副本中将要求改成 `zlib >= 999.0`，加入真实安装目录：返回 `PC016`，指出同一依赖声明与实际版本不符。
3. 使用原始的 `zlib >= 1.2.13` 要求和真实安装目录，取得无诊断的构建计划，再调用编译器。
4. 压缩并解压空文件、文本文件和 512 KiB 二进制文件，核对每一个字节。另由 Python 标准库 zlib 解码程序输出，再让程序解码 Python 生成的数据；Python 只在这一步作为互操作对照。
5. 检查损坏输入不会生成结果，已有输出文件内容得到保留。

成功时输出：

```text
Published consumer: 2 dependency failures, repaired build and 3 interoperable file round trips passed
```

`evidence.json` 保存失败时的诊断、成功时的参数及来源、依赖路径和输入摘要。项目的 `.pc` 是应用自身的真实依赖声明，故障在其独立副本中构造；zlib 元数据来自实际安装。这是本项目维护的独立消费者示例，不代表已有外部用户采用。

## 来源与验证

本目录使用 MIT 许可证。C 包装层复用本项目的 zlib FFI 示例，只保留压缩与解压入口；API 参考 [zlib 手册](https://zlib.net/manual.html)。文件与路径操作使用 `moonbitlang/x@0.5.5` 的公开 API，遵循其 Apache-2.0 许可证，不复制其实现。

主仓库的 `scripts/verify-zlib-consumer.py` 会把整个目录复制到仓库之外的系统临时目录，下载普通 MoonCakes 依赖并执行完整演示。Ubuntu CI 在固定 zlib 1.3.1 安装上运行；Windows CI 用同版本 MSVC 安装的正确引用空格路径副本运行。该验证不依赖主分支尚未发布的源码。

仓库验证脚本另将报告保存为 `_build/verification/zlib-consumer.json`，双平台 CI 会上传对应的 `published-consumer` 附件，供下载核对。
