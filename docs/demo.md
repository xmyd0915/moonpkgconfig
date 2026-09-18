# 可复现演示

以下命令在仓库根目录运行。需要已安装 MoonBit 工具链；首次运行先执行 `moon update` 下载模块依赖。

## 1. 运行测试

```sh
moon check --target all --deny-warn
moon test --target all --deny-warn
```

预期四个目标均通过。目前每个目标运行 46 个逻辑测试。

## 2. 检查正常文件

```sh
moon run --target native cmd/inspect examples/imagekit.pc
```

输出包含包名、版本、依赖、编译和链接参数，并标明原文件行号；最后一行为 `Diagnostics: none`，进程退出码为 `0`。

## 3. 检查错误文件

```sh
moon run --target native cmd/inspect examples/broken.pc
```

该样例有未定义变量、无分隔符文本、空名称、缺失描述和带空白的版本。命令会一次报告这五项问题，进程退出码为 `1`。

## 4. 输出 JSON

```sh
moon run --target native cmd/inspect examples/imagekit.pc --json
```

JSON 保留每个变量和字段的原始值、展开值及来源位置，也包含诊断数组。它可供其他命令行工具、编辑器或 CI 继续处理。

## 退出码

| 退出码 | 含义 |
| --- | --- |
| `0` | 文件读取成功且没有诊断 |
| `1` | 文件读取成功，但解析或必填元数据检查发现问题 |
| `2` | 参数用法错误或文件无法读取 |

当前文件入口一次处理一个 UTF-8 `.pc` 文件，不搜索系统 pkg-config 目录。完整兼容边界见仓库 README。
