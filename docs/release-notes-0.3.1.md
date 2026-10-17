# MoonPkgConfig 0.3.1 发行说明

模块：`xmyd0915/moonpkgconfig@0.3.1`；许可证：MIT。正式上传、源码标签及注册表下载安装结果见 [发布记录](https://github.com/xmyd0915/moonpkgconfig/blob/main/docs/release.md)。

## 修复损坏依赖的诊断

应用通过 `Requires: helper` 使用 `helper.pc`，而该文件包含未定义变量时，旧的文件加载器会排除这个包，后续查询把问题报告为应用依赖声明处的 `PC015`。本版把加载时的原始诊断传入查询，返回 `helper.pc` 中真正出错的位置，例如第1行第8列的 `PC004`。真正没有对应文件时仍返回 `PC015`。

新增可选参数 `unavailable : Map[String, Array[Diagnostic]]`，用于 `resolve`、`check_all`、`collect_cflags`、`collect_libs`、`dependency_path` 和 `dependency_paths`。从原生文件适配层接入时：

```moonbit
let loaded = @loader.load_directories(directories)
let result = loaded.packages.collect_libs(
  root,
  static_linking=true,
  unavailable=loaded.diagnostics_by_package,
)
```

现有调用无需增加参数。核心库仍只接收内存数据，没有文件系统依赖。

查询只返回实际使用到的失败依赖：动态链接忽略私有依赖，编译及静态链接按原有规则包含它们。同一失败依赖被多条路径引用时，原始诊断只返回一次。有效精确包优先；被排除的同名文件阻止虚拟提供者回退；空诊断条目不阻止回退。失败映射不跨调用缓存，下一次查询可看到修复后的数据。

目录命令另汇总所有加载错误，不为已知损坏文件追加虚假的缺包诊断。路径接口遵循相同的精确包与提供者规则。

## 实际使用示例

新增 [通用原生接入模板](../examples/native-consumer/README.md)，由配置选择根包、静态模式、C/C++ 包装源和 MoonBit 导入。同一个规划器和构建适配层分别接入真实 zlib 与 Expat；模板可复制到仓库外独立使用。

该模板固定使用已发布的0.3.0，作为已有接口的使用基线；文件压缩消费者仍固定0.2.0。它们不使用0.3.1新增的诊断参数。模板支持单个根目录可执行包；复杂构建系统可消费规划器的 JSON。完整故障、修复与构建流程见 [原生演示](native-walkthrough.md)。

## 验收范围

- 89项核心逻辑测试分别在四个后端运行，包含8项新增诊断回归。
- 22个文件加载 CLI 场景验证错误码、真实文件和行列、私有模式、目录顺序、虚拟提供者及修复后重新加载。
- 独立归档消费者新增2项测试，总计6项，直接导入新增可选参数；已发布0.3.0仍运行原4项消费者测试。
- 对实际 ZIP 提取的源码执行四目标检查、源码和消费者测试，再从归档内运行22个文件加载场景。
- 保留162项固定 pkgconf 对照、158个输入场景、大图与展开边界、真实原生库集成和0.2.0/0.3.0消费者。

具体命令及执行结果见 [验证记录](verification.md)。归档验证和正式注册表安装是两条不同证据；正式上传后另以 `python scripts/verify-install.py --version 0.3.1` 验证注册表安装，结果记入发布记录。已发布归档和标签保持原内容。

正式发行的安装命令：

```sh
moon add xmyd0915/moonpkgconfig@0.3.1
```
