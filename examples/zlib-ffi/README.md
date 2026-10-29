# 用真实 zlib 构建 MoonBit FFI 程序

这个示例把 MoonPkgConfig 的查询结果用于 MoonBit 自身的原生构建：读取已安装的 `zlib.pc`，查询 Cflags 和静态 Libs，生成独立模块的原生编译配置，再调用 zlib 的 CRC-32、压缩和解压 API。

Linux 或 macOS 需要 MoonBit、Python 3.9+、POSIX C 编译器，以及包含头文件、静态库和 `zlib.pc` 的 zlib 开发安装。Windows x64 的 MSVC 流程见下文。复现使用 MoonBit `0.10.16+b1a0e846e`。

在仓库根目录运行，传入实际安装目录：

```sh
python3 scripts/verify-zlib-ffi.py --pc-dir /path/to/zlib/lib/pkgconfig
```

Ubuntu 的 `zlib1g-dev` 通常可使用：

```sh
python3 scripts/verify-zlib-ffi.py \
  --pc-dir "/usr/lib/$(cc -print-multiarch)/pkgconfig"
```

`--cc` 可选择 C 编译器，`--moon` 可指定 MoonBit CLI。脚本打印读取到的 zlib 版本与参数，成功时输出：

```text
MoonBit zlib FFI: CRC-32, 3 round trips and 3 error cases passed
```

验证包括标准 CRC-32 向量 `123456789`、空输入、文本和 4096 字节二进制输入的压缩/解压，以及损坏数据、目标缓冲区过小和非法长度三种错误。C 包装层使用 MoonBit 的借用调用约定，并在解压前检查长度，避免越界读取。

## Windows MSVC

需要 Windows x64、MoonBit、Python 3.9+、CMake 3.15+、Visual Studio C++ 工具和 Windows SDK。在仓库根目录运行：

```powershell
python scripts/verify-zlib-windows.py
```

脚本从官方归档下载 zlib 1.3.1，检查下文的 SHA-256，用 MSVC 与静态运行库 `/MT` 构建并安装，再读取上游生成、未经修改的 `zlib.pc`。它自动发现 Visual Studio，环境调整只影响本次进程及子进程。`--cmake` 和 `--moon` 可指定工具路径；`--archive` 可使用已下载的同版本归档，仍会校验哈希。源码、安装和构建日志保留在 `.tmp/windows-zlib-*`。

随后复制安装到 `zlib with spaces`，在副本的 `.pc` 中更新前缀，并给 `-I`、`-L` 的路径变量加引号，再次构建运行。zlib 1.3.1 的原始模板没有这些引号，不能直接表示带空格的安装路径；这个检查使用正确引用路径的独立副本，原始安装文件保持不变。

已有 MSVC zlib 开发安装时，可直接运行：

```powershell
python scripts/verify-zlib-ffi.py `
  --pc-dir C:/libraries/zlib/share/pkgconfig `
  --msvc-lib z=zlibstatic.lib
```

上游 CMake 构建的静态库名为 `zlibstatic.lib`，元数据仍使用 `-lz`，因此用 `--msvc-lib NAME=FILE.lib` 显式指定；其他安装方式应填写实际的静态库文件名。静态库应与 MoonBit 使用相同的 x64 架构和 `/MT` 运行库。没有映射的 `-lNAME` 转为 `NAME.lib`，不猜测发行版库名。

示例适配器只转换连接式或分离式 `-I/-D/-U` 与 `-L/-l`，保留顺序，并拒绝未知选项或跨来源操作数。它从 JSON 数组生成 MSVC 配置，补充 `/utf-8`、`/MT` 与链接器分隔符 `/link`；MoonBit 自动发现编译器，或用 `--cc` 指定已配置的 `cl`/`clang-cl`。这不改变核心库返回的原始参数，也不代表通用的 MSVC 或 MinGW 兼容层。

成功时最后输出 `Windows MSVC zlib integration: 2 installations passed`。Windows CI 每次执行这两个安装场景；`python scripts/test-native-ffi.py` 另检查引用边界、库名映射、来源隔离和拒绝未知选项。完整本地验证可用 `./scripts/verify.ps1 -WithWindowsZlib`，也可附加 `-CMake` 指定路径。

脚本使用 JSON 参数数组，不调用外部 pkg-config，不通过 shell 执行元数据。生成的模块放在忽略的 `.tmp` 目录，运行结束后自动清理；源码和示例配置保持不变。`examples/zlib-ffi/moon.pkg` 是基础配置，实际链接参数由脚本从查询结果补齐。

Ubuntu 与 Windows CI 均从官方发行包构建 zlib 1.3.1，再读取安装生成的 `.pc` 并运行本示例。库源码、编译产物和安装路径均不提交到本仓库。API 依据 [zlib 手册](https://zlib.net/manual.html)，FFI 与配置方式依据 [MoonBit 官方文档](https://docs.moonbitlang.com/en/stable/language/ffi.html)及[原生包配置](https://docs.moonbitlang.com/en/stable/toolchain/moon/package.html#default-c-compiler-and-compiler-flags-for-the-native-backend)。

固定下载：<https://github.com/madler/zlib/releases/download/v1.3.1/zlib-1.3.1.tar.gz>；SHA-256：`9a93b2b7dfdac77ceba5a558a580e74667dd6fede4585b91eefb60f03b72df23`。
