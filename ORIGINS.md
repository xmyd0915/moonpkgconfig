# 来源与实现方式

项目使用 MIT 许可证，著作权声明为 MoonPkgConfig contributors。

## 参考资料

1. pkgconf 项目 `.pc` 格式文档：<https://github.com/pkgconf/pkgconf/blob/main/man/pc.5>。
2. pkgconf 版本比较接口文档：<https://pkgconf.readthedocs.io/en/latest/libpkgconf-pkg.html>，用于核对比较结果约定和 RPM 风格规则；固定标签3.0.7的 `libpkgconf/pkg.c` 用于核对 `Provides` 比较矩阵，并以发行版命令复验行为。
3. pkg-config Guide：<https://people.freedesktop.org/~dbn/pkg-config-guide.html>，供补充阅读；兼容性判断以固定版本 pkgconf 的文档、命令与差分结果为准。
4. MoonBit 官方语言及包配置文档：<https://docs.moonbitlang.com/en/latest/>。
5. MoonBit 标准库（工具链自带）：<https://github.com/moonbitlang/core>，Apache-2.0；本项目使用 API，不复制其实现。
6. `moonbitlang/x` 0.5.5：<https://github.com/moonbitlang/x>，Apache-2.0；`cmd/inspect` 使用其 `fs` 和 `path` API 读取文件及计算 `pcfiledir`，依赖源码不纳入本仓库。

本项目依据公开格式独立编写，没有移植或复制 pkgconf/pkg-config/MoonNinja/MoonGitAttrs 的实现代码。功能单元测试与 `examples` 中的 `.pc` 示例均为本项目自编。

`testdata/pkgconf-3.0.7` 中的11个兼容样本未经修改地复制自pkgconf官方测试套件标签 `pkgconf-3.0.7`（提交 `0c9e506b64124d8727b68d8af0ed73739e66e2ba`），并随附上游ISC许可证。文件清单与原始路径见该目录README。

`testdata/real-world` 保存 zlib 1.3.1 与 libffi 3.4.6 的官方 `.pc.in` 模板内容，只把文件后缀改为 `.pc` 供目录加载器直接检查；`templates/` 另存未经改写的 libuv 1.48.0、libpng 1.6.59、PCRE2 10.44 与 Expat 2.6.2 模板。目录README及 `corpus.json` 记录固定提交、上游路径、模板与完整许可证的 SHA-256、配置替换值及边界。配置副本仅用于测试，不代表实际安装。

`scripts/verify-compatibility.py` 为本项目编写，使用清单声明的独立预期值、固定 pkgconf 3.0.7 和 Python 标准库 `shlex` 验证查询与参数边界。随机和异常输入由固定种子生成；不复制参考工具实现。`Cflags.private` 的静态顺序依据固定 pkgconf 的格式文档、公开命令和 `libpkgconf/pkg.c` 核对。

`examples/zlib-ffi` 中的 MoonBit 程序、C 包装和运行脚本为本项目编写，API 用法参考 <https://zlib.net/manual.html>。CI 在临时目录构建官方 zlib 1.3.1 发行包；不把 zlib 实现或编译产物纳入本仓库。

`examples/zlib-consumer` 是本项目维护的独立消费示例，直接依赖 MoonCakes 0.2.0 公开接口。文件工具的 C 包装复用上述示例的压缩/解压入口；真实安装元数据不作修改，项目自己的依赖声明副本用于故障演示。Python 标准库 zlib 仅在互操作检查中作为独立对照，不实现应用程序或元数据查询。

`examples/libpng-ffi` 中的 MoonBit 程序与 C 包装同样为本项目编写，API 用法参考 <https://www.libpng.org/pub/png/libpng-manual.txt>。CI 从官方发行包安装 libpng 1.6.59，使用安装生成的元数据检查其对 zlib 的私有依赖，再运行 PNG 编解码。库源码和编译产物不纳入本仓库；固定下载及校验值见示例 README。

## 非代码验证工具

`examples/expat-ffi` 的 MoonBit 程序、C 包装及构建脚本为本项目编写，API 用法核对 Expat 官方文档及固定发行包的公开头文件。回归使用官方2.6.2源码包，固定归档 SHA-256；完整库源码和编译产物不进入仓库。实际安装生成的 `.pc` 不改写，Python 标准库 `xml.parsers.expat` 仅作为独立安装的解析结果对照，其版本记录在报告。来源、构建及负对照见示例 README。

已使用官方 pkgconf 3.0.7 Windows x64 发行版对自编三包依赖图和错误样例进行对照，只运行公开命令并记录结果。工具二进制不进入仓库，也不随本项目重新许可；详细版本、哈希和差异见 `docs/pkgconf-comparison.md`。
