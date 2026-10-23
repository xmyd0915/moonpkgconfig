# 快速体验指南

MoonPkgConfig 解决的是原生库接入时“参数从哪里来、依赖为什么失败、结果能否稳定交给其他工具”的问题。核心解析与依赖计算使用 MoonBit 编写，不启动 shell，也不调用系统 `pkg-config`。

## 查询与诊断

安装 MoonBit 工具链并在仓库根目录运行。当前 CI 固定使用 `0.10.14+7d59c7ec9`，建议复现时使用相同版本：

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

## 从发布包构建实际文件工具

在查询之后，可以使用同一套通用接入代码构建 zlib、Expat 和文件压缩器：

```sh
python scripts/review-native.py
```

需要 Python 3.9+、CMake 3.15+ 和原生构建环境：Linux 使用 C 编译器和 `make`，Windows 使用 Visual Studio C++ 工具及 Windows SDK。脚本检查工具、准备固定版本的静态库，再在仓库之外使用已发布的 MoonCakes 0.3.1。它串联缺失、版本错误、损坏文件定位、修复与实际执行，并核对三个应用使用相同的规划器和适配器。

生成的文件工具支持 `compress <输入> <输出.zlib>` 和 `decompress <输入.zlib> <输出>`，验证涵盖空文件、文本、二进制和 Python zlib 双向互操作。程序一次处理整个文件，压缩输入及解压输出上限为 64 MiB，拒绝覆盖已有输出。应用均由本项目维护，不代表第三方采用。

结果、实际耗时和可执行文件路径保存在 `_build/verification/native-walkthrough.json`。准备选项、复用已有安装、执行生成程序和三个详细报告见 [完整原生流程](native-walkthrough.md)。

## 验证记录

| 关注点 | 仓库证据 |
| --- | --- |
| MoonBit 实现与多目标可用性 | 主分支89个逻辑测试分别在 wasm、wasm-gc、JavaScript、native 运行，含5,000包长链及目录检查；0.3.0发行源码为81项 |
| 与既有工具的行为关系 | 原38项加六项目模板120项、静态字段顺序4项，共162项固定 pkgconf 3.0.7 差分 |
| 真实输入 | zlib、libffi、libuv、libpng、PCRE2、Expat 六项目模板及11个官方 pkgconf 测试文件；默认种子另验证158个生成输入 |
| 原生使用闭环 | 查询参数后编译 C 静态库、链接并运行 C++ 调用程序 |
| MoonBit 接入真实 C 库 | `examples/zlib-ffi` 从已安装的 zlib 元数据取得构建参数，由 MoonBit 调用 CRC-32、压缩和解压；CI 从固定版本源码安装并验证 |
| 真实多库依赖 | `examples/libpng-ffi` 使用 libpng → zlib 私有依赖，验证跨目录查询和缺失依赖诊断，再静态构建 MoonBit PNG 编解码程序 |
| 静态编译要求 | `examples/expat-ffi` 从真实安装的 `Cflags.private` 取得 `XML_STATIC`，验证 XML 分块解析、错误与 Python 独立安装对照；MSVC 移除/恢复该字段验证实际链接影响 |
| 已发布库的独立使用 | `examples/zlib-consumer` 直接依赖 MoonCakes 0.2.0，读取真实 zlib 安装，重现缺失依赖和版本错误，再构建文件压缩程序并进行双向互操作检查；验证副本放在仓库之外 |
| 来源与许可证 | `ORIGINS.md`、MIT许可证以及随样本保存的上游许可证 |
| 复用同一接入代码 | `examples/native-consumer` 固定依赖 MoonCakes 0.3.1，在仓库外通过配置和应用源码构建 zlib、Expat、文件压缩工具；验证依赖故障、修复、真实运行和来源，总入口比较规划器与适配器摘要 |
| 损坏依赖定位 | 0.3.1包含22个文件加载 CLI 场景，保留依赖的原始文件错误 |
| 独立环境复现 | `.github/workflows/ci.yml` 与 `docs/verification.md` 中的公开运行记录 |

真实原生库示例的前置条件和命令见 [zlib](../examples/zlib-ffi)、[libpng](../examples/libpng-ffi)、[Expat](../examples/expat-ffi) 与 [发布包消费者](../examples/zlib-consumer)。四个场景均在 Ubuntu CI 验证，zlib、Expat 与发布包消费者另有 Windows MSVC CI；示例使用独立原生模块，不增加核心库的外部依赖。

已有 zlib 开发安装时，运行 `python scripts/verify-zlib-consumer.py --pc-dir <安装元数据目录>` 可看到故障、来源解释、修复和实际文件操作。Windows 的 zlib CMake 静态库另加 `--msvc-lib z=zlibstatic.lib`。需要自动准备固定 zlib 的 Windows 环境可用 `python scripts/verify-zlib-windows.py --with-consumer`，详细前置条件见 zlib 示例。

## 边界

通用模板适用于单个根目录可执行包，支持通过应用配置声明导入和原生接口文件。已有自定义 `moon.pkg` 或 `moon.pkg.json` 会被拒绝；更复杂的构建系统应直接集成规划器 JSON。模板的损坏依赖诊断映射从 0.3.1 起提供。

项目当前是面向常用 `.pc` 解析、检查和参数查询的0.3.1实现，不宣称完整替代 pkg-config/pkgconf。目录、系统路径和 sysroot 由调用方显式提供；尚不自动读取系统搜索路径，不实现 Windows 自动重定位及全部 pkgconf 扩展。
