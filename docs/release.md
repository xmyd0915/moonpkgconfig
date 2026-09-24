# 发布准备

## 当前状态

- 模块版本为 `0.1.0`，许可证为 MIT，仓库地址已写入 `moon.mod`。
- `moon package --list` 已进入本地验证与 CI，必须包含核心源码、README、许可证和来源说明，且不能包含构建目录、工具缓存或登录凭据。
- 核心库和命令行工具均通过四目标检查；原生 CLI 在 Windows 与 Ubuntu 验证。
- 当前模块名 `local/moonpkgconfig` 是开发期占位名，尚未发布到 MoonCakes。

## 首次发布前需要维护者完成

1. 登录 MoonCakes，确认账号对应的模块命名空间。
2. 把 `moon.mod` 的 `name` 以及各 `moon.pkg` 中的内部导入从 `local/moonpkgconfig` 统一替换为最终名称。
3. 重新执行 `scripts/verify.ps1`，确认四目标测试、CLI、C/C++ 闭环、pkgconf 差分和打包清单全部通过。
4. 检查 `CHANGELOG.md`、版本号和 Git 工作区，创建对应 GitHub Release。
5. 执行 `moon login` 后再运行 `moon publish`。登录凭据不得进入仓库或验证记录。

首次发布属于外部账号操作。在命名空间确认前保留占位名，避免发布到错误名称后再迁移。
