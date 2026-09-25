# 评审快速入口

MoonPkgConfig 解决的是原生库接入时“参数从哪里来、依赖为什么失败、结果能否稳定交给其他工具”的问题。核心解析与依赖计算使用 MoonBit 编写，不启动 shell，也不调用系统 `pkg-config`。

## 五分钟复现

安装 MoonBit 工具链并在仓库根目录运行：

```sh
moon update
sh scripts/review-demo.sh
```

Windows PowerShell：

```powershell
./scripts/review-demo.ps1
```

脚本依次展示四件事：

1. 查询 Cflags，并把每个参数追溯到依赖路径、包、字段、文件与行号；
2. 一次报告错误目录中的解析、元数据和依赖问题，并验证失败退出码；
3. 对编译参数应用显式 sysroot，展示可复现的交叉编译路径处理；
4. 使用官方 pkgconf 3.0.7 样本，分别接受和拒绝两个带范围的虚拟依赖。

成功时最后显示 `Reviewer walkthrough: passed`。该脚本也在 GitHub Actions 中运行，演示步骤不会只在维护者电脑上成立。

## 证据位置

| 关注点 | 仓库证据 |
| --- | --- |
| MoonBit 实现与多目标可用性 | 59 个逻辑测试分别在 wasm、wasm-gc、JavaScript、native 运行 |
| 与既有工具的行为关系 | 22 项输出或退出码与固定 pkgconf 3.0.7 自动差分 |
| 真实输入 | zlib 1.3.1、libffi 3.4.6 模板及11个官方 pkgconf 测试文件 |
| 原生使用闭环 | 查询参数后编译 C 静态库、链接并运行 C++ 调用程序 |
| 来源与许可证 | `ORIGINS.md`、MIT许可证以及随样本保存的上游许可证 |
| 独立环境复现 | `.github/workflows/ci.yml` 与 `docs/verification.md` 中的公开运行记录 |

## 边界

项目当前是面向常用 `.pc` 解析、检查和参数查询的 0.1.0 实现，不宣称完整替代 pkg-config/pkgconf。目录、系统路径和 sysroot 由调用方显式提供；尚不自动读取系统搜索路径，不实现 Windows 自动重定位及全部 pkgconf 扩展。
