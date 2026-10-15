# 来源与实现方式

项目使用 MIT 许可证，著作权声明为 MoonPkgConfig contributors。

## 参考资料

1. pkgconf 项目 `.pc` 格式文档：<https://github.com/pkgconf/pkgconf/blob/main/man/pc.5>。
2. pkgconf 版本比较接口文档：<https://pkgconf.readthedocs.io/en/latest/libpkgconf-pkg.html>，用于核对比较结果约定和 RPM 风格规则；固定标签3.0.7的 `libpkgconf/pkg.c` 用于核对 `Provides` 比较矩阵，并以发行版命令复验行为。
3. pkg-config Guide：<https://people.freedesktop.org/~dbn/pkg-config-guide.html>。本次访问被站点拒绝，不能作为本次已读取证据。
4. MoonBit 官方语言及包配置文档：<https://docs.moonbitlang.com/en/latest/>。
5. MoonBit 标准库（工具链自带）：<https://github.com/moonbitlang/core>，Apache-2.0；本项目使用 API，不复制其实现。
6. `moonbitlang/x` 0.5.5：<https://github.com/moonbitlang/x>，Apache-2.0；`cmd/inspect` 使用其 `fs` 和 `path` API 读取文件及计算 `pcfiledir`，依赖源码不纳入本仓库。

本项目依据公开格式独立编写，没有移植或复制 pkgconf/pkg-config/MoonNinja/MoonGitAttrs 的实现代码。功能单元测试与 `examples` 中的 `.pc` 示例均为本项目自编。

`testdata/pkgconf-3.0.7` 中的11个兼容样本未经修改地复制自pkgconf官方测试套件标签 `pkgconf-3.0.7`（提交 `0c9e506b64124d8727b68d8af0ed73739e66e2ba`），并随附上游ISC许可证。文件清单与原始路径见该目录README。

`testdata/real-world` 保存 zlib 1.3.1 与 libffi 3.4.6 的官方 `.pc.in` 模板内容，只把文件后缀改为 `.pc` 供目录加载器直接检查。目录README记录固定提交、上游路径和替换标记边界，并随附各自许可证。

`examples/zlib-ffi` 中的 MoonBit 程序、C 包装和运行脚本为本项目编写，API 用法参考 <https://zlib.net/manual.html>。CI 在临时目录构建官方 zlib 1.3.1 发行包；不把 zlib 实现或编译产物纳入本仓库。

`examples/libpng-ffi` 中的 MoonBit 程序与 C 包装同样为本项目编写，API 用法参考 <https://www.libpng.org/pub/png/libpng-manual.txt>。CI 从官方发行包安装 libpng 1.6.59，使用安装生成的元数据检查其对 zlib 的私有依赖，再运行 PNG 编解码。库源码和编译产物不纳入本仓库；固定下载及校验值见示例 README。

## 非代码验证工具

已使用官方 pkgconf 3.0.7 Windows x64 发行版对自编三包依赖图和错误样例进行对照，只运行公开命令并记录结果。工具二进制不进入仓库，也不随本项目重新许可；详细版本、哈希和差异见 `docs/pkgconf-comparison.md`。
