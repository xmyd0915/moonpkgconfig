# MoonPkgConfig 0.4.1

0.4.1 修正 `query --variable`，并将多包工程的依赖检查提前到配置阶段。源码构建使用 `moonc 0.10.21+06da1ed44` 和 `moon 0.1.20261117`。

```sh
moon add xmyd0915/moonpkgconfig@0.4.1
```

## 查询变量

当变量由文件加载器或 `--define-variable` 提供时，0.4.0 可以用它展开字段，但直接查询可能得到 `not_found`。在仓库根目录运行以下命令可以查询元数据文件所在目录，以及调用方传入的变量。

```sh
moonpkgconfig query examples/valid imagekit --variable=pcfiledir
moonpkgconfig query examples/valid imagekit --define-variable=custom=/sdk/custom --variable=custom --json
```

`pcfiledir` 取自实际选中的包，也适用于虚拟包选中的提供者。第二条命令查询的 `custom` 可以只在命令行提供，返回 `status: "ok"` 和 `value: "/sdk/custom"`。显式提供空值同样成功，JSON 的 `value` 为空字符串。查询 `pc_sysrootdir` 时默认返回空字符串，可通过 `--define-variable=pc_sysrootdir=/sdk` 指定值。目录搜索顺序和来源信息见 [CLI JSON 接口](cli-json.md)。

## 原生构建

- [多包工程示例](../examples/project-integration/README.md) 在配置时用实际规划器检查每个原生绑定。缺包或版本不满足时，可以在开始构建应用之前定位失败的绑定。
- Ubuntu 上的 [Cairo 兼容性脚本](../scripts/verify-cairo-binding.sh) 下载并校验 `tonyfettes/cairo@0.2.0`，在临时环境中将该绑定原有构建脚本的 `--cflags` 和 `--libs` 查询交给 MoonPkgConfig，运行绑定自带的原生测试。这项兼容性检查由 MoonPkgConfig 项目维护。

## 安装 CLI

Linux x86_64 和 Windows x86_64 的发行 ZIP 使用版本号和平台命名，校验后解压即可运行。包内 `build-info.json` 提供准确的源码提交和工具链版本。操作步骤见 [独立命令行下载指南](cli-download.md)。
