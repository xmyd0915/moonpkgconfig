# 来源与实现方式

项目使用 MIT 许可证，著作权声明为 MoonPkgConfig contributors。

## 参考资料

1. pkgconf 项目 `.pc` 格式文档：<https://github.com/pkgconf/pkgconf/blob/main/man/pc.5>。
2. pkgconf 版本比较接口文档：<https://pkgconf.readthedocs.io/en/latest/libpkgconf-pkg.html>，用于核对比较结果约定和 RPM 风格规则。
3. pkg-config Guide：<https://people.freedesktop.org/~dbn/pkg-config-guide.html>。本次访问被站点拒绝，不能作为本次已读取证据。
4. MoonBit 官方语言及包配置文档：<https://docs.moonbitlang.com/en/latest/>。
5. MoonBit 标准库（工具链自带）：<https://github.com/moonbitlang/core>，Apache-2.0；本项目使用 API，不复制其实现。
6. `moonbitlang/x` 0.5.5：<https://github.com/moonbitlang/x>，Apache-2.0；`cmd/inspect` 使用其 `fs` 和 `path` API 读取文件及计算 `pcfiledir`，依赖源码不纳入本仓库。

本项目依据公开格式独立编写，没有移植或复制 pkgconf/pkg-config/MoonNinja/MoonGitAttrs 的实现代码。功能单元测试与 `examples` 中的 `.pc` 示例均为本项目自编。

`testdata/pkgconf-3.0.7` 中的10个兼容样本未经修改地复制自pkgconf官方测试套件标签 `pkgconf-3.0.7`（提交 `0c9e506b64124d8727b68d8af0ed73739e66e2ba`），并随附上游ISC许可证。文件清单与原始路径见该目录README。

`testdata/real-world` 保存 zlib 1.3.1 与 libffi 3.4.6 的官方 `.pc.in` 模板内容，只把文件后缀改为 `.pc` 供目录加载器直接检查。目录README记录固定提交、上游路径和替换标记边界，并随附各自许可证。

开发过程中使用了 AI 辅助；项目方向、功能取舍、验证与发布由维护者负责。维护者理解实现、核对结果并维护真实的开发记录。

## 非代码验证工具

已使用官方 pkgconf 3.0.7 Windows x64 发行版对自编三包依赖图和错误样例进行对照，只运行公开命令并记录结果。工具二进制不进入仓库，也不随本项目重新许可；详细版本、哈希和差异见 `docs/pkgconf-comparison.md`。
