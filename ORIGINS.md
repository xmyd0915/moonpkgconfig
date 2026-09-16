# 来源与实现方式

项目使用 MIT 许可证，著作权声明为 MoonPkgConfig contributors。

## 参考资料

1. pkgconf 项目 `.pc` 格式文档：<https://github.com/pkgconf/pkgconf/blob/main/man/pc.5>。
2. pkg-config Guide：<https://people.freedesktop.org/~dbn/pkg-config-guide.html>。本次访问被站点拒绝，不能作为本次已读取证据。
3. MoonBit 官方语言及包配置文档：<https://docs.moonbitlang.com/en/latest/>。
4. MoonBit 标准库（工具链自带）：<https://github.com/moonbitlang/core>，Apache-2.0；本项目使用 API，不复制其实现。

本项目依据公开格式独立编写，没有移植或复制 pkgconf/pkg-config/MoonNinja/MoonGitAttrs 的实现代码。当前测试与 `.pc` 示例均为本项目自编，不含来源不明的语料。后续若引入外部测试，必须逐项记录出处、版本与许可证。

开发过程中使用了 AI 辅助；项目方向、功能取舍、验证与发布由维护者负责。维护者理解实现、核对结果并维护真实的开发记录。

## 非代码验证工具

计划使用官方 pkgconf/pkg-config 作为对照工具，只运行公开接口并比较结果；当前尚未宣称完成该对照。其代码不随本项目重新许可。
