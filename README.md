# MoonPkgConfig

[English](README.en.md) · [MoonCakes](https://mooncakes.io/docs/xmyd0915/moonpkgconfig) · [下载](https://github.com/xmyd0915/moonpkgconfig/releases/tag/v0.4.0) · [发行说明](docs/release-notes-0.4.0.md)

[![CI](https://github.com/xmyd0915/moonpkgconfig/actions/workflows/ci.yml/badge.svg)](https://github.com/xmyd0915/moonpkgconfig/actions/workflows/ci.yml)

用 MoonBit 实现的 `pkg-config` 元数据引擎，面向原生 FFI、构建工具和 CI。读取 `.pc` 文件、解析依赖、计算编译与链接参数，并把每个参数追溯到包、字段、文件位置和依赖路径。

核心库为纯 MoonBit，支持 wasm、wasm-gc、JavaScript 和 native；解析和查询不启动 shell，也不调用外部 `pkg-config`。

| 需要完成的工作 | 使用入口 |
| --- | --- |
| 在 MoonBit 中解析元数据、计算参数 | `moon add xmyd0915/moonpkgconfig@0.4.0` |
| 检查文件、查询依赖或接入其他语言的构建工具 | `moonpkgconfig inspect / query / check`，支持 JSON |
| 构建真实原生应用 | [zlib、Expat、文件压缩工具模板](examples/native-consumer/README.md) |
| 接入已有多包工程 | [实验性 pre-build 集成](examples/project-integration/README.md) |

0.4.0 提供统一 CLI 和版本化 JSON，修复共享依赖的链接顺序，完善文件诊断、私有依赖校验和解析资源限制。升级行为见 [发行说明](docs/release-notes-0.4.0.md)，具体版本的归档、标签与安装结果见 [发布记录](docs/release.md)。

## 安装与快速体验

源码构建使用 `moonc 0.10.20+65efd5b93`、`moon 0.1.20261104`，并需要本机 C 编译工具。安装 [MoonBit](https://www.moonbitlang.com/download/) 后运行：

```sh
git clone https://github.com/xmyd0915/moonpkgconfig.git
cd moonpkgconfig
moon update
moon install ./cmd/moonpkgconfig
moonpkgconfig query examples/valid imagekit --libs --static --json --explain
moonpkgconfig inspect examples/valid/imagekit.pc --json
moonpkgconfig check examples/invalid --json
```

最后一条命令检查错误样本，显示文件位置并返回退出码 1。安装目录需要在 `PATH` 中；也可用 `moon install ./cmd/moonpkgconfig --bin <目录>` 指定位置。安装后能离开仓库运行，三个子命令均支持 `--help`。

不安装 MoonBit 也可以使用打包的 Linux 或 Windows 可执行文件。下载入口、适用平台、许可证和校验步骤见 [独立命令行下载](docs/cli-download.md)。

查询自己的原生安装时，显式传入 `.pc` 目录和包名：

```sh
moonpkgconfig query /path/to/sdk/lib/pkgconfig zlib --modversion
moonpkgconfig query /path/to/sdk/lib/pkgconfig zlib --cflags
moonpkgconfig query /path/to/sdk/lib/pkgconfig zlib --libs --static --explain
moonpkgconfig check /path/to/sdk/lib/pkgconfig --path /path/to/extra/pkgconfig --json
```

多个目录按命令行顺序查找，同名文件由第一个目录确定。`--explain` 展示参数来源与依赖路径；程序集成使用 `--json`，保留完整参数边界。

## 在 MoonBit 中使用

在已有模块中执行 `moon add xmyd0915/moonpkgconfig@0.4.0`，为下面的测试在 `moon.pkg` 中添加：

```moonbit
import {
  "xmyd0915/moonpkgconfig" @pc,
} for "test"
```

以下是一个可运行的测试；保存为 `example_test.mbt` 后执行 `moon test`：

```moonbit
test "query a native library" {
  let input =
    #|Name: codec
    #|Description: Example native library
    #|Version: 1.0
    #|Libs: -lcodec
    #|Libs.private: -lm
  let document = @pc.parse(input, source="codec.pc")
  let packages = @pc.PackageSet::new()
  assert_true(packages.add("codec", document).is_empty())
  let result = packages.collect_libs("codec", static_linking=true)
  assert_true(result.diagnostics.is_empty())
  assert_eq(result.flags[0].value, "-lcodec")
  assert_eq(result.flags[1].value, "-lm")
  assert_eq(result.flags[1].field, "Libs.private")
  assert_eq(result.flags[1].location.source, "codec.pc")
}
```

`parse` 保留原始值、展开值和行列位置；`PackageSet` 接收内存中的文档，解析公开/私有依赖、版本约束、冲突和虚拟提供者。`collect_cflags` / `collect_libs` 返回带来源的参数数组，`dependency_paths` 提供最短依赖路径。读取版本和变量可使用不遍历依赖的 `PackageSet::select`。

核心库不访问文件系统。原生文件加载和命令行交互在适配层实现；公开接口见 [MoonCakes 文档](https://mooncakes.io/docs/xmyd0915/moonpkgconfig)。

## 从构建工具调用

```python
import json
import subprocess

result = subprocess.run(
    ["moonpkgconfig", "query", "./pkgconfig", "example", "--libs", "--json"],
    capture_output=True, text=True, encoding="utf-8", check=False,
)
report = json.loads(result.stdout)
if result.returncode != 0 or report["schema_version"] != 1 or report["status"] != "ok":
    raise RuntimeError(report)
arguments = [flag["value"] for flag in report["flags"]]
```

把 `arguments` 作为参数数组传给编译器，不再次执行或拆分 shell 文本。JSON 位于 stdout，stderr 应保持独立；文本查询失败时诊断写入 stderr，stdout 不输出部分参数。完整结构和调用契约见 [CLI JSON 接口](docs/cli-json.md)。

| 退出码 | 含义 |
| --- | --- |
| `0` | 成功，或版本条件满足 |
| `1` | 元数据/单文件加载诊断、缺少变量或版本条件不满足 |
| `2` | 调用错误、搜索目录读取失败或 inspect 文件读取失败 |

`--exists`、版本条件和所有 CLI 参数查询检查公开与私有依赖；动态 `--libs` 仍只输出公开链接参数。`--modversion` 与 `--variable=名称` 只验证所选根。无关坏文件不会阻断正常包查询，首个损坏文件仍保留同名优先级。

## 真实原生应用

[通用模板](examples/native-consumer/README.md) 用同一个 MoonBit 规划器和构建适配器接入 zlib、Expat 与文件压缩工具。它读取安装生成的 `.pc`，解释依赖故障，修复后计算参数并构建应用。在仓库根目录运行：

```sh
python scripts/review-native.py
```

该命令准备固定版本的静态库，在仓库外运行消费者，检查压缩文件与 Python zlib 的双向互操作，并打印可执行文件位置。需要 Python 3.9+、CMake 3.15+；Linux 需要 C 编译器和 `make`，Windows 需要 Visual Studio C++ 工具及 Windows SDK。依赖版本、已有安装的复用方法和平台边界见 [原生接入指南](docs/native-walkthrough.md)。

[多包工程示例](examples/project-integration/README.md) 保留已有的包配置，通过实验性 pre-build 钩子接入正常的 `moon build/run/test`；运行 `python scripts/verify-project-integration.py` 可重现。钩子接口与固定工具链绑定。另有 Ubuntu 上的 [libpng → zlib 示例](examples/libpng-ffi/README.md)，验证真实私有依赖和 PNG 像素往返。

## 验证与开发

```sh
moon version --all
moon check --target all --deny-warn
moon build --target all --deny-warn
moon test --target all --deny-warn
python scripts/verify-cli.py
python scripts/verify-install.py --package
```

[GitHub Actions](https://github.com/xmyd0915/moonpkgconfig/actions/workflows/ci.yml) 在 Ubuntu 与 Windows 执行四目标检查、构建、测试，验证实际安装的 CLI、源码归档消费者和真实原生应用。兼容检查使用固定的 pkgconf 3.0.7，覆盖上游样本、六个项目模板、随机输入、系统安装语料及移除依赖后的失败路径；真实静态库的编译、链接和运行单独验证。

复现命令、工具版本和每次执行的结果见 [开发指南](DEVELOPMENT.md)、[验证记录](docs/verification.md)、[兼容性检查](docs/compatibility.md) 与 [性能记录](docs/query-performance.md)。CI 报告记录对应源码提交，不用某次测试结果代表所有环境。

## 兼容范围

- 支持 UTF-8、LF/CRLF、开头 BOM、注释、续行、按定义顺序展开的变量，以及已知字段名的 ASCII 大小写变体；保留原文与位置。变量名和未知扩展字段区分大小写。
- 支持版本约束、`Provides`、`Conflicts`、`Requires.private`、`Libs.private`、`Cflags.private` 和五种参数分类。静态编译字段仅在 `--static` 时加入。
- 重复定义、未定义变量和依赖环采用严格诊断；CLI 根参数只接受一个包名，不接受版本表达式。
- 单值和每文档累计展开预算均为 1,048,576 个 UTF-16 code units；首次超限返回 `PC009` 并停止。解析器保留前 100 条诊断，下一条触发 `PC021` 并停止。这些限制不是输入文件大小或整个进程的内存上限。
- 搜索目录、sysroot 和系统路径过滤均由调用方显式指定，不读取 `PKG_CONFIG_*` 环境变量。已带 sysroot 前缀的路径不会重复添加。
- 来源行是逻辑行起始的物理行；列为合并续行并处理注释后的 Unicode 字符列。续行中间不提供精确物理跨度。
- 不实现完整 pkgconf 兼容、Windows 自动重定位或全部片段去重。原生示例仅转换明确支持的编译选项，未知选项返回错误。

项目采用 [MIT 许可证](LICENSE)。固定上游样本、版本、来源与各自许可证见 [ORIGINS.md](ORIGINS.md)；后续方向见 [ROADMAP.md](ROADMAP.md)。
