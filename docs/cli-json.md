# CLI JSON 接口

本页描述当前主分支统一 `moonpkgconfig` 和三个旧命令入口的机器输出。它是命令行报告协议，不改变核心库的 `Document.as_json()`、`FlagResult.as_json()`，也不表示注册表0.3.1已包含新增 CLI。

## 调用与退出码

```sh
moonpkgconfig inspect example.pc --json
moonpkgconfig check ./pkgconfig --path ./extra --json
moonpkgconfig query ./pkgconfig example --libs --static --json --explain
moonpkgconfig query ./pkgconfig example --modversion --json
moonpkgconfig query ./pkgconfig example --variable=prefix --json
moonpkgconfig query ./pkgconfig example --atleast-version=1.2 --json
```

对已识别的 `inspect`、`query`、`check` 子命令，指定 `--json` 后，正常结果、元数据诊断、用法错误和文件读取错误均在 stdout 输出一个 JSON 对象。`--help`/`-h` 优先输出文本帮助；顶层帮助和未知子命令不属于此协议。系统 IO 的补充说明可能出现在 stderr，不应将两条流合并后解析。

未使用 JSON 时，失败的诊断、用法和 IO 信息写入 stderr；参数查询失败时 stdout 为空，不输出部分参数。目录检查失败时汇总也写入 stderr。显式帮助仍写入 stdout；正常 `--explain` 包含来源说明，适合阅读，程序调用应选择 JSON。

| 退出码 | 含义 |
| --- | --- |
| `0` | 查询或检查成功；条件查询满足要求 |
| `1` | 解析/语义或单文件加载诊断、缺少变量或版本条件不满足，具体原因由 `status` 区分 |
| `2` | 调用方式、搜索目录读取错误，或 inspect 指定文件的 IO 错误 |

不要仅以“JSON 能解析”判断成功。消费者应同时检查退出码、`schema_version` 和 `status`；允许新增对象字段，不按字段顺序解析，也不要依赖错误消息的措辞。

## 公共字段

| 字段 | 类型与含义 |
| --- | --- |
| `schema_version` | 整数，当前为 `1` |
| `command` | `inspect`、`query` 或 `check` |
| `status` | `ok`、`diagnostics`、`usage_error`、`io_error`；query 另有 `nonmatch`、`not_found` |
| `diagnostics` | 数组，保留核心库诊断的 `code`、`message`、`location`；位置含 `source`、`line`、`column` |
| `error` | 无调用/IO/变量错误时为 `null`；否则为对象，例如 `{ "kind": "io", "message": "..." }`；kind 可为 `usage`、`io`、`variable` |

`diagnostics` 包含 `.pc` 的解析、语义及已选文件的加载诊断。query/check 中单个 `.pc` 条目读不了时返回 `PC019`，无效 UTF-8 返回 `PC020`，位置指向该文件，`status` 为 `diagnostics`、`error` 为 `null`、退出码为1。坏条目仍占据其包名，后续同名文件不能覆盖；无关坏条目不污染单包查询。搜索目录读取失败与用法错误则使用 `error` 和退出码2，不返回部分成功。版本比较正常完成但不满足条件时，`status` 为 `nonmatch`，`error` 为 `null`。

## inspect

额外返回 `file`（请求文件名，未提供时为 `null`）和原有 `entries` 数组。成功或元数据诊断时，条目仍包含 `kind`、`name`、`raw`、`value`、`location`、`value_location`；用法或 IO 失败时 `entries`、`diagnostics` 为空，必须根据状态识别失败。

非 UTF-8 文件返回 `PC020`、空条目和退出码1，不把解码失败当成缺少必填字段。单文件读取失败仍是 `io_error` 和退出码2。加载器提供的默认 `pc_sysrootdir` 仅用于变量展开，不是原始条目，不增加虚构的来源位置。

## query

| 字段 | 类型与含义 |
| --- | --- |
| `directories` | 显式搜索目录数组，第一位置参数在前，随后按 `--path` 顺序排列 |
| `package` | 请求包名；未提供时为 `null`，虚拟包查询仍保留请求名 |
| `mode` | 完整模式字符串，如 `--libs`、`--variable=prefix`、`--atleast-version=1.2`；未指定时为 `null` |
| `static` | 是否请求静态编译/链接参数 |
| `flags` | 原有参数对象数组，每项含 `value`、`package`、`field`、`location`；不改变参数顺序、重复库或参数边界 |
| `value` | 成功的 `--modversion`、`--variable=...` 查询返回字符串，其余情况为 `null` |
| `matched` | `--exists` 与版本条件正常求值后返回布尔值，发生诊断/IO/用法错误或其他模式时为 `null` |
| `paths` | 正常参数查询加 `--explain` 时，返回参数所属包名到最短依赖路径数组的映射；其余情况为 `null` |

例如 `paths` 可包含 `{"codec": ["imagekit", "codec"]}`。它解释当前返回的参数，按参数项的 `package` 关联；保留既有 `flags` 元素结构。编译参数路径包含私有依赖，动态链接只包含公开依赖，静态链接包含私有依赖。

根参数只接受一个包标识符。`--exists`、`--atleast-version`、`--exact-version`、`--max-version` 都检查私有依赖；私有依赖损坏时返回诊断且 `matched=null`。`--modversion` 和变量读取不检查私有依赖。参数数组沿用核心结果：链接参数采用依赖者在前的顺序，编译参数保留广度优先顺序。

不存在的变量返回 `not_found`、`error.kind = "variable"`、`value = null` 与退出码1。已定义的空变量是成功的空字符串。版本不符返回 `nonmatch`、`matched = false` 与退出码1；查询失败尚未完成比较时，`matched` 为 `null`，不能解释成版本不符。

JSON 可用于全部查询模式。`--static`、路径过滤、去重和 `--explain` 仍只适用于参数模式；一次只能选择一个查询模式。JSON 与文本查询遵循相同的搜索优先级、变量覆盖、版本和虚拟提供者规则。

## check

额外字段为 `directories`、`file_count`、`package_count`、`package_ids`。`file_count` 包括被前面目录遮蔽的同名文件；`package_ids` 仅含成功加载且被选中的包。首个损坏文件仍占据该包名，后面的有效文件不能掩盖它。

搜索目录读取和用法失败时两个计数为 `null`，包名与诊断数组为空，不把部分加载结果报告为成功或空目录。单个 `.pc` 条目的读取/解码诊断则保留扫描计数，并汇总为退出码1；`file_count` 包括名为 `.pc` 的非普通文件条目。

## Python 调用示例

```python
import json
import subprocess

result = subprocess.run(
    ["moonpkgconfig", "query", "./pkgconfig", "example", "--libs", "--json"],
    capture_output=True, text=True, encoding="utf-8", check=False,
)
report = json.loads(result.stdout)
if report["schema_version"] != 1:
    raise RuntimeError("Unsupported CLI report version")
if result.returncode != 0:
    raise RuntimeError(json.dumps(report, ensure_ascii=False))
arguments = [flag["value"] for flag in report["flags"]]
# Pass arguments as an argv list to a compiler; do not evaluate shell text.
```

Windows 可指定 `moonpkgconfig.exe` 的绝对路径。子进程无法启动属于宿主调用错误，不会有 CLI JSON。可下载包与校验方法见 [独立命令行](cli-download.md)。
