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
| MoonBit 实现与多目标可用性 | 78 个逻辑测试分别在 wasm、wasm-gc、JavaScript、native 运行，含5,000包长链及目录检查 |
| 与既有工具的行为关系 | 38 项输出或退出码与固定 pkgconf 3.0.7 自动差分，含五种参数分类 |
| 真实输入 | zlib 1.3.1、libffi 3.4.6 模板及11个官方 pkgconf 测试文件 |
| 原生使用闭环 | 查询参数后编译 C 静态库、链接并运行 C++ 调用程序 |
| MoonBit 接入真实 C 库 | `examples/zlib-ffi` 从已安装的 zlib 元数据取得构建参数，由 MoonBit 调用 CRC-32、压缩和解压；CI 从固定版本源码安装并验证 |
| 真实多库依赖 | `examples/libpng-ffi` 使用 libpng → zlib 私有依赖，验证跨目录查询和缺失依赖诊断，再静态构建 MoonBit PNG 编解码程序 |
| 已发布库的独立使用 | `examples/zlib-consumer` 直接依赖 MoonCakes 0.2.0，读取真实 zlib 安装，重现缺失依赖和版本错误，再构建文件压缩程序并进行双向互操作检查；验证副本放在仓库之外 |
| 来源与许可证 | `ORIGINS.md`、MIT许可证以及随样本保存的上游许可证 |
| 独立环境复现 | `.github/workflows/ci.yml` 与 `docs/verification.md` 中的公开运行记录 |

真实原生库示例的前置条件和命令见 [zlib](../examples/zlib-ffi)、[libpng](../examples/libpng-ffi) 与 [发布包消费者](../examples/zlib-consumer)。三个场景均在 Ubuntu CI 验证，zlib 与发布包消费者另有 Windows MSVC CI；示例使用独立原生模块，不增加核心库的外部依赖。

已有 zlib 开发安装时，运行 `python scripts/verify-zlib-consumer.py --pc-dir <安装元数据目录>` 可看到故障、来源解释、修复和实际文件操作。Windows 的 zlib CMake 静态库另加 `--msvc-lib z=zlibstatic.lib`。需要自动准备固定 zlib 的 Windows 环境可用 `python scripts/verify-zlib-windows.py --with-consumer`，详细前置条件见 zlib 示例。

## 边界

项目当前是面向常用 `.pc` 解析、检查和参数查询的 0.2.0 实现，不宣称完整替代 pkg-config/pkgconf。目录、系统路径和 sysroot 由调用方显式提供；尚不自动读取系统搜索路径，不实现 Windows 自动重定位及全部 pkgconf 扩展。
