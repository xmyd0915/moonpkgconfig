# 选题检索记录

检索日期：2026-09-16，Asia/Shanghai。

结论：选择 MoonPkgConfig，开发纯 MoonBit `.pc` 元数据解析与依赖解释工具。公开检索未发现直接等价库，但这不代表所有未公开项目都不存在；赛事群选题确认尚未完成。

## 已核查证据

- MoonCakes 公开目录接口 <https://mooncakes.io/api-new/v0/modules> 返回 2,504 项。对包名、描述、关键词检索 `pkg-config`、`pkgconfig`、`pkgconf`、`moonpc`、编译/链接参数及原生依赖相关关键词，未命中专用实现。
- GitHub 公开仓库搜索 `pkg-config language:MoonBit` 返回 0 项，`MoonPkgConfig OR pkgconf language:MoonBit` 返回 0 项；这些搜索不等于覆盖所有仓库内部源码。
- Web 搜索 `MoonBit pkgconf`、`MoonBit pkg-config parser library`、`site:mooncakes.io pkg-config`，发现 tonyfettes/cairo 调用外部 pkg-config 发现 Cairo 库，属于潜在使用场景，而非独立 `.pc` 解析库：<https://mooncakes.io/docs/tonyfettes/cairo>。
- 候选 depfile 方向排除：MoonNinja 已有 Make 风格依赖文件解析：<https://www.gitlink.org.cn/Zcxxffss/MoonNinja>；MoonCakes 另有 Zcxssxx/moon-ninja。
- 原 MoonGitAttrs 方向排除：Xpeng/moongitattrs 已覆盖解析、匹配、求值和解释，仓库 <https://github.com/pxgt/moongitattrs>。API 记录版本 0.1.0 创建时间为 2026-09-15T03:52:04Z；早先搜索缓存的“3 小时前”不能用于判断实际发布时间。
- <https://moonbitlang.github.io/Hackathon2026/> 已核实月度新项目、9 月 24 日节点、公开仓库、实质工作、MoonBit 为主、来源及许可证、允许 AI 和加入交流群要求。未获取到完整九月参赛项目名单，不能声称对报名项目已全部去重。

## 选择理由

真实用户是 MoonBit Native/FFI 和构建工具开发者。核心工作包含词法边界、顺序变量求值、带版本的依赖图、私有依赖与链接行为，具有独立工程内容。验收可用自编样例与成熟 pkgconf 工具对照，不依赖主观演示效果。

不承诺通过审核或获得奖金。正式申报应说明兼容子集和现有状态，避免将路线图写为已完成功能。
