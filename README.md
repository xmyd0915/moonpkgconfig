# MoonPkgConfig

用 MoonBit 读取、检查和解释 C 库的 `pkg-config` 元数据（`.pc` 文件）。

面向原生 FFI 和构建工具开发者：查看编译参数从哪个字段与变量产生，定位未定义变量、重复字段和错误依赖表达式。核心库为纯 MoonBit，读取与求值不调用外部 `pkg-config`。

## 当前状态

首个开发里程碑，尚未发布到 MoonCakes。`local/moonpkgconfig` 仅供本地导入；公开发布前由维护者确认实际命名空间。

已实现：变量与字段解析、注释和续行、顺序变量展开、`pcfiledir` 输入、来源位置、错误恢复、必填元数据校验、编译/链接参数分词、`Requires` 依赖表达式解析、版本比较及约束判断。

下一阶段：CLI 文件查询、官方工具对照测试和兼容策略细化。当前仍不能替代完整的 `pkg-config`/`pkgconf`。

## 快速运行

需要 MoonBit 工具链。本地开发版本为 `moon 0.1.20260915`。

```sh
moon check --target all
moon test --target all
moon run cmd/demo
```

演示输出示例：

```text
Name: imagekit [imagekit.pc:4]
Version: 1.2.0 [imagekit.pc:6]
Libs: -L/opt/example/lib -limagekit [imagekit.pc:9]
Cflags: -I/opt/example/include -DIMAGEKIT=1 [imagekit.pc:11]
Requires: codec >= 2.0 [imagekit.pc:7]
Requires.private: compression >= 1.0 [imagekit.pc:8]
```

Windows 当前工作区可运行 `./scripts/verify.ps1`。它只为本次进程设置便携工具链环境；也可通过 `-MoonHome` 指定其他安装位置。

## 库接口

```moonbit
let doc = @pc.parse(
  "prefix=/opt/sdk\nLibs: -L${prefix}/lib -lcodec\n",
  source="codec.pc",
)
let libs = doc.field("Libs")
```

`Entry` 同时返回 `raw`（原始值）、`value`（展开值）、`location`（文件/行/列）。变量按定义顺序展开，非法条目不会进入查询结果；应先检查 `Document.diagnostics`。

`Document::validate_metadata` 检查 `Name`、`Description` 和 `Version`，与保留错误继续解析的文本层分开，便于编辑器展示多个问题。

`split_flags` 返回参数数组，不启动 shell；`parse_requirements` 返回包名、比较运算符和版本文本。`compare_versions` 和 `Requirement::matches` 可用于检查已安装版本是否满足约束。

`PackageSet` 接收已解析文档并检查直接依赖，报告重复包、缺失包和版本不满足。`PackageSet::resolve` 生成依赖优先的传递顺序，按需包含 `Requires.private`，并诊断循环依赖及带版本条件的 `Conflicts`。找不到同名包时，可按加入顺序选择 `Provides` 中无版本或精确版本匹配的虚拟包提供者；范围形式的 `Provides` 仍留待后续兼容工作。

`collect_cflags` 与 `collect_libs` 聚合依赖图中的参数，每个参数保留包名、字段和来源位置。静态链接查询会加入私有依赖与 `Libs.private`。

`Document::json_text` 和 `FlagResult::json_text` 提供紧凑或缩进 JSON，供命令行工具、编辑器与 CI 使用。

项目在公开前已有几天的选题、学习和本地原型探索；2026-09-16 整理为公开仓库，此后的实现与验证通过公开提交持续记录。

## 兼容范围

- 支持 LF、CRLF、UTF-8 文本对应的 MoonBit 字符串、开头 BOM、`#` 注释、`\#` 字面量、反斜杠续行。
- 支持 `${name}`、`$${...}` 字面量及调用者提供的 `pcfiledir`。不读取环境变量。
- 重复字段、重复变量、覆盖 `pcfiledir`、未定义引用采用严格错误诊断；不同于某些宽松实现。
- 来源行是逻辑行起始的物理行；列为合并续行并处理注释后的 Unicode 字符列。续行中间的精确物理跨度还未实现。
- 仅解析文本，不查找系统包、不修改构建配置、不运行编译器或安装依赖。
- 尚不实现 sysroot 重写、Windows 自动重定位、系统路径过滤、完整片段去重、版本比较或 pkgconf 3 扩展。

来源与许可证见 [ORIGINS.md](ORIGINS.md)，开发计划见 [ROADMAP.md](ROADMAP.md)。MIT 许可证全文见 [LICENSE](LICENSE)。
