# 可复现演示

以下命令在仓库根目录运行。需要已安装 MoonBit 工具链；首次运行先执行 `moon update` 下载模块依赖。

## 1. 运行测试

```sh
moon check --target all --deny-warn
moon test --target all --deny-warn
```

预期四个目标均通过。目前每个目标运行 47 个逻辑测试。

## 2. 检查正常文件

```sh
moon run --target native cmd/inspect examples/valid/imagekit.pc
```

输出包含包名、版本、依赖、编译和链接参数，并标明原文件行号；最后一行为 `Diagnostics: none`，进程退出码为 `0`。

## 3. 检查错误文件

```sh
moon run --target native cmd/inspect examples/invalid/broken.pc
```

该样例有未定义变量、无分隔符文本、空名称、缺失描述和带空白的版本。命令会一次报告这五项问题，进程退出码为 `1`。

## 4. 输出 JSON

```sh
moon run --target native cmd/inspect examples/valid/imagekit.pc --json
```

JSON 保留每个变量和字段的原始值、展开值及来源位置，也包含诊断数组。它可供其他命令行工具、编辑器或 CI 继续处理。

## 5. 查询依赖图参数

```sh
moon run --target native cmd/query examples/valid imagekit --cflags --explain
moon run --target native cmd/query examples/valid imagekit --libs
moon run --target native cmd/query examples/valid imagekit --libs --dedupe-paths
moon run --target native cmd/query examples/valid imagekit --libs --static
```

目录中包含 `imagekit -> codec -> compression` 三个包。第一条命令还会显示每个参数来自哪个包、字段和源码行；第三条只去除重复的 `-L` 搜索路径，结果与对照使用的 pkgconf 动态链接输出一致；最后一条展示静态链接结果。

## 6. 一次检查整个目录

```sh
moon run --target native cmd/check examples/valid
moon run --target native cmd/check examples/invalid
```

第一条命令应显示 `Checked 3 packages from 3 .pc files; 0 diagnostics.` 并返回 `0`。第二条会同时报告文件语法问题、未定义变量、公开依赖缺失和私有依赖缺失，最后显示 `4 diagnostics` 并返回 `1`。

## 7. 检查固定的上游样本

```sh
moon run --target native cmd/check testdata/pkgconf-3.0.7
```

预期显示 `Checked 10 packages from 10 .pc files; 0 diagnostics.`。这些文件未经修改地取自官方pkgconf 3.0.7测试套件，具体来源、提交和许可证记录在同目录README中。

## 退出码

| 退出码 | 含义 |
| --- | --- |
| `0` | 输入读取成功且没有诊断 |
| `1` | 输入读取成功，但解析、元数据或依赖检查发现问题 |
| `2` | 参数用法错误或输入无法读取 |

所有命令都只读取明确给出的 UTF-8 文件或目录，不搜索系统 pkg-config 目录。完整兼容边界见仓库 README。
