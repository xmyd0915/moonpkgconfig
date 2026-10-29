# 用 libpng 和 zlib 验证私有依赖接入

这个示例从真实安装的 `libpng16.pc` 和 `zlib.pc` 查询参数，在独立 MoonBit 原生模块中编码 PNG、解码并逐字节比较 RGBA 像素。libpng 的元数据通过 `Requires.private: zlib` 声明依赖，因此可用实际构建检验普通查询与静态查询的区别。

需要 Linux 或 macOS、MoonBit `0.10.16+b1a0e846e`、Python 3、POSIX C 编译器，以及带头文件、静态库和 `.pc` 的 libpng/zlib 安装。当前示例未适配 Windows MSVC。

在仓库根目录运行：

```sh
python3 scripts/verify-libpng-ffi.py \
  --pc-dir /path/to/libpng/lib/pkgconfig \
  --path /path/to/zlib/lib/pkgconfig
```

`--path` 可重复追加有序搜索目录。系统安装将两个 `.pc` 放在同一目录时，只传 `--pc-dir` 即可；`--moon` 和 `--cc` 可指定工具。CI 把两个库静态安装到不同前缀，确保查询需要跨目录解析真实依赖，并实际使用静态库链接。

脚本检查：

- 普通 `--libs` 不纳入 zlib 私有依赖的参数；Cflags 和静态 Libs 包含来自 zlib 的参数与来源记录。
- 将未经修改的 `libpng16.pc` 复制到独立临时目录，普通 Libs 查询仍成功；Cflags 和静态查询必须以退出码1及 `PC015` 报告缺失 zlib。查询不会隐式回退到系统目录。
- 使用完整静态参数构建并运行 MoonBit PNG 程序。程序验证1×1、8×8和17×9图像的编码/解码及逐字节像素一致性，另检查损坏PNG、错误尺寸、输出缓冲区不足及输入长度越界四种错误。

成功时最后输出：

```text
MoonBit libpng FFI: 3 RGBA round trips and 4 error cases passed
```

PNG 包装层只适配示例中的 RGBA 内存接口，返回非负长度表示成功，`-1` 表示非法输入参数，`-2` 表示编解码失败，`-3` 表示尺寸不符，`-4` 表示输出空间不足。这些是本示例定义的返回值。长度和尺寸在访问缓冲区前检查，借用参数不保存到 C 侧。

构建脚本读取 MoonPkgConfig 的 JSON 数组，不调用系统 pkg-config；配置和运行产物位于忽略的临时目录并自动清理。核心库不依赖 libpng 或 zlib。CI 另行重跑原有 zlib 示例，核对共用构建脚本的兼容性。

固定依赖和来源：

- libpng 1.6.59：[官方页面](https://www.libpng.org/pub/png/libpng.html)、[源码归档](https://downloads.sourceforge.net/project/libpng/libpng16/1.6.59/libpng-1.6.59.tar.gz)。官方 SHA-256：`86a3e4b501f7f50e392c4e456ea158893e9a595b1c63eb88c7bb9f6cf8772dad`。
- zlib 1.3.1：版本、归档和校验值同 [zlib 示例](../zlib-ffi)。
- API 参考 [libpng 官方手册](https://www.libpng.org/pub/png/libpng-manual.txt)的 Simplified API。库源码、许可证和编译产物留在 CI 临时安装目录，不作为本项目源码重新发布。
