# MoonBit 原生元数据工具的历史检索记录

检索日期：2026-09-16，Asia/Shanghai。

以下保留当日的有限公开生态检索结果，不描述当前生态状态，也不证明不存在其他实现。MoonPkgConfig 面向纯 MoonBit `.pc` 元数据解析与依赖解释。

## 当日记录

- MoonCakes 公开目录接口 <https://mooncakes.io/api-new/v0/modules> 返回 2,504 项。对包名、描述、关键词检索 `pkg-config`、`pkgconfig`、`pkgconf`、`moonpc`、编译/链接参数及原生依赖相关关键词，未命中专用实现。
- GitHub 公开仓库搜索 `pkg-config language:MoonBit` 返回 0 项，`MoonPkgConfig OR pkgconf language:MoonBit` 返回 0 项；这些搜索不等于覆盖所有仓库内部源码。
- Web 搜索 `MoonBit pkgconf`、`MoonBit pkg-config parser library`、`site:mooncakes.io pkg-config`，发现 tonyfettes/cairo 调用外部 pkg-config 发现 Cairo 库，属于潜在使用场景，而非独立 `.pc` 解析库：<https://mooncakes.io/docs/tonyfettes/cairo>。

## 适用场景

目标使用场景是 MoonBit Native/FFI 和构建工具中的依赖查询：需要处理词法边界、顺序变量求值、带版本的依赖图、私有依赖与链接行为，并返回参数来源。上述生态记录不代表所列项目使用了 MoonPkgConfig；当前实现与兼容范围以 README 和验证记录为准。
