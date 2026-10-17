# 从依赖错误到真实原生构建

这条演示串联两种能力：0.3.1准确报告损坏依赖的原始错误；可独立复制的通用模板直接使用已发布的 MoonCakes 0.3.0，驱动真实原生构建。诊断映射从0.3.1起提供，模板使用的接口都已在0.3.0提供。

## 准备

需要固定的 MoonBit `0.10.14+7d59c7ec9`、Python 3.9+、CMake 和 C 编译器。Windows 使用 x64 Visual Studio C++ 工具及 Windows SDK。首次下载还需要网络；准备脚本校验固定源码归档的 SHA-256，保留构建日志及安装目录。

Windows 可在仓库根目录准备 zlib 1.3.1 和 Expat 2.6.2：

```powershell
python scripts/verify-zlib-windows.py
python scripts/verify-expat.py
```

脚本分别打印 `.tmp/windows-zlib-*/` 与 `.tmp/expat-*/` 工作目录。zlib 安装副本的 `.pc` 位于 `zlib with spaces/share/pkgconfig`，Expat 位于 `installed/lib/pkgconfig`。这些版本用于可重复的回归验证。

Linux 可使用已有静态安装的 `lib/pkgconfig` 目录；固定版本 zlib 的安装步骤见 CI，Expat 仍可使用上面的 Python 脚本。Ubuntu CI 使用同一模板分别运行两个消费者。

## 一条命令演示

将下面两个路径替换为实际安装目录：

```powershell
python scripts/review-native.py --zlib-pc-dir ".tmp/windows-zlib-<工作目录>/zlib with spaces/share/pkgconfig" --expat-pc-dir ".tmp/expat-<工作目录>/installed/lib/pkgconfig" --zlib-msvc-lib z=zlibstatic.lib
```

Linux 使用相应目录并省略 `--zlib-msvc-lib`。脚本不会改写安装文件，故障与修复发生在独立副本中。

1. 复制真实 `expat.pc`，加入 `broken=${missing}`。查询应用的静态编译参数应返回 `PC004`，定位到依赖文件第1行第8列。
2. 移除该定义后重新查询，恢复真实安装参数，包含来自 `Cflags.private` 的 `-DXML_STATIC`。
3. 把通用模板复制到仓库外，实际使用 MoonCakes 0.3.0。演示 zlib 缺失、版本不满足和修复，再构建运行 CRC-32、压缩/解压及错误检查。
4. 使用同样的模板代码、更换应用配置与源码，构建运行 Expat 的分块 XML 解析。Python 独立安装核对计数、状态、错误和位置。

报告保存在 `_build/verification/native-walkthrough.json` 和两个 `native-consumer-*.json`；报告包含真实参数及来源、版本、依赖路径和运行结果。文件路径会随本机安装和临时目录变化。CI 分别执行故障位置检查与两个真实消费者，并上传双平台附件。

## 集成到自己的项目

复制 [通用模板](../examples/native-consumer/README.md)，按其中说明修改 `consumer.json`、应用 `.pc` 与 C/C++ 包装接口即可。它适用于单个根目录可执行包；较大的构建系统可直接消费规划器 JSON。

对于使用0.3.1 API 的原生适配层，把文件加载器的失败映射传入查询：

```moonbit
let loaded = @loader.load_directories(directories)
let result = loaded.packages.collect_libs(
  root,
  static_linking=true,
  unavailable=loaded.diagnostics_by_package,
)
```

`resolve`、`check_all`、`collect_cflags`、`collect_libs` 及两个依赖路径接口支持这个可选映射。只有当前遍历实际使用的失败依赖会影响查询；目录检查另汇总全部加载错误。同一失败依赖被多个分支引用时原始诊断只返回一次。有效精确包优先；被排除的同名文件阻止虚拟提供者回退。核心仍只接收内存数据，不增加文件系统依赖。此参数不能用于已发布的0.3.0。
