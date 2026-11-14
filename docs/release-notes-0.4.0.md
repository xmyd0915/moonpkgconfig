# MoonPkgConfig 0.4.0

模块：`xmyd0915/moonpkgconfig@0.4.0`；许可证：MIT。本版提供可独立安装的命令行工具，并修复影响真实原生构建的依赖排序、文件诊断和私有依赖校验问题。

```sh
moon add xmyd0915/moonpkgconfig@0.4.0
```

源码复现使用 `moonc 0.10.20+65efd5b93` 和 `moon 0.1.20261104`。源码标签、上传归档、注册表安装结果见 [发布记录](release.md)；可执行文件和校验步骤见 [命令行下载](cli-download.md)。

## 命令行与构建工具接口

统一命令包含 `inspect`、`query`、`check` 三个子命令。在仓库根目录执行 `moon install ./cmd/moonpkgconfig` 后，可以离开仓库直接运行；原有 `moon run cmd/inspect`、`cmd/query`、`cmd/check` 入口继续复用同一实现。

```sh
moonpkgconfig query examples/valid imagekit --libs --static --json --explain
moonpkgconfig query examples/valid imagekit --modversion --json
moonpkgconfig check examples/valid --path /path/to/extra/pkgconfig --json
```

三个子命令的 JSON 报告使用 `schema_version: 1`，保留条目、参数、来源和诊断，增加请求上下文、状态及明确错误。版本和变量查询返回 `value`，条件查询返回 `matched`；`--json --explain` 提供参数所属包到最短依赖路径的映射。目录检查保留搜索顺序、扫描条目数和选中包名。完整契约见 [CLI JSON 接口](cli-json.md)。

文本模式的诊断、用法和 IO 错误统一写入 stderr。失败的参数查询保持 stdout 为空，避免构建工具把诊断当成编译参数。JSON 保持在 stdout；调用方应同时检查退出码、状态和 schema 版本。

## 参数顺序与依赖语义

当 `app` 依赖 `base, mid`，且 `mid` 依赖 `base` 时，旧版可能输出 `-lapp -lbase -lmid`，导致单次扫描的静态链接器找不到 `mid` 使用的符号。本版输出 `-lapp -lmid -lbase`。完整依赖图中公开可达库之间的私有关系也参与动态链接排序，但不会把私有库参数加入动态结果。

Cflags 按完整公开/私有依赖图排序，让依赖者先于依赖，独立分支按声明顺序完成。`Requires.private` 的普通编译参数在动态和静态模式均包含；只有静态模式追加 `Cflags.private`，并且在所有普通 Cflags 之后按同一包顺序追加。字段内参数与重复项保留，只有显式 `--dedupe-paths` 去重搜索目录。

CLI 的 `--exists`、三个版本条件及所有参数模式都检查私有依赖。动态 `--libs` 只输出公开参数，但不再接受无法完整解析的安装。`--modversion` 和 `--variable=名称` 只检查所选根包，缺失的依赖不会阻止读取根元数据。

新增 `PackageSet::select(root, source=..., unavailable=...)`，返回所选精确包或虚拟提供者的 `Result[Package, Array[Diagnostic]]`，不遍历依赖和冲突字段。原有核心 `collect_libs` 的私有错误范围仍由 `static_linking` 控制；CLI 在动态查询前另行校验完整图。调用方修改公开包集合或文档后，缺失版本和缺失引用返回诊断。

## 文件、字段与资源边界

- 单个 `.pc` 条目读取失败返回 `PC019`，无效 UTF-8 返回 `PC020`，位置指向真实文件。无关坏条目不阻断正常查询；第一个坏文件仍占据其包名，后面的同名文件或虚拟提供者不能掩盖它。搜索目录读取失败仍返回退出码 2。
- 已知字段名支持 ASCII 大小写变体，例如 `CFlags`，并保留原始拼写、位置和重复定义检查。变量名和未知扩展字段保持区分大小写。
- 加载器为 `pc_sysrootdir` 提供默认空值，显式 `--sysroot` 同时供变量展开和路径重写使用。已经具有该目录前缀的路径不再重复添加。
- 单值及每文档累计展开上限均为 1,048,576 个 UTF-16 code units，包括调用方覆盖值；首次 `PC009` 立即停止该文档。
- 解析器保留前 100 条诊断，下一条触发 `PC021` 并停止。诊断合并按完整内容进行哈希去重，保留首次出现顺序。停止后的未解析字段不会被额外报告为缺失元数据。

展开和诊断预算不等于输入文件大小或进程内存上限。文件适配层仍会读取文件内容；处理不受信任的目录时，调用方需要根据自己的运行环境限制输入和进程资源。

## 原生集成

[通用消费者](../examples/native-consumer/README.md) 使用同一规划器和适配器构建 zlib、Expat 与真实文件压缩工具。完整流程准备固定静态库，展示依赖故障及修复，检查源位置、文件往返和 Python zlib 双向互操作。文件工具限制输入/输出规模、独占创建输出文件，失败信息写入 stderr。

[已有工程接入](../examples/project-integration/README.md) 使用实验性 pre-build 配置钩子，保留各包的自定义配置，向库包及其使用者传递原生参数。规划器先独立构建，钩子执行已构建程序并重新加载元数据，不递归启动 MoonBit 构建。该接口与固定工具链绑定，适用布局和选项范围见示例说明。

## 验证方式

```sh
moon version --all
moon check --target all --deny-warn
moon build --target all --deny-warn
moon test --target all --deny-warn
python scripts/verify-cli.py
python scripts/verify-install.py --package
```

验证流程包括四目标核心测试、仓库外安装的 CLI、实际 ZIP 的独立消费者、原生集成和资源边界。pkgconf 3.0.7 对照覆盖 187 项固定查询及 158 个固定种子输入；系统语料还检查参数序列、实际展开总量和删除依赖后的失败查询。原始系统文件保持不变，缺依赖检查在副本中执行。真实静态链接用三个依赖图分别编译、链接和运行。

执行结果与机器报告按源码提交记录在 [验证记录](verification.md) 和 [兼容性检查](compatibility.md)。这些检查覆盖声明的功能与场景，不代表完整替代 pkgconf。既有发行归档和标签保持原内容。
