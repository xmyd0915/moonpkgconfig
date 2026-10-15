# 用真实 zlib 构建 MoonBit FFI 程序

这个示例把 MoonPkgConfig 的查询结果用于 MoonBit 自身的原生构建：读取已安装的 `zlib.pc`，查询 Cflags 和静态 Libs，生成独立模块的原生编译配置，再调用 zlib 的 CRC-32、压缩和解压 API。

需要 Linux 或 macOS、MoonBit、Python 3、POSIX C 编译器，以及包含头文件、静态库和 `zlib.pc` 的 zlib 开发安装。当前示例未适配 Windows 的 MSVC 参数约定。

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

脚本使用 JSON 参数数组，不调用外部 pkg-config，不通过 shell 执行元数据。生成的模块放在忽略的 `.tmp` 目录，运行结束后自动清理；源码和示例配置保持不变。`examples/zlib-ffi/moon.pkg` 是基础配置，实际链接参数由脚本从查询结果补齐。

CI 从官方发行包构建 zlib 1.3.1，再读取安装生成的 `.pc` 并运行本示例。库源码、编译产物和安装路径均不提交到本仓库。API 依据 [zlib 手册](https://zlib.net/manual.html)，FFI 与配置方式依据 [MoonBit 官方文档](https://docs.moonbitlang.com/en/stable/language/ffi.html)。

固定下载：<https://github.com/madler/zlib/releases/download/v1.3.1/zlib-1.3.1.tar.gz>；SHA-256：`9a93b2b7dfdac77ceba5a558a580e74667dd6fede4585b91eefb60f03b72df23`。
