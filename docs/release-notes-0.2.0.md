# MoonPkgConfig 0.2.0 发行说明

模块名称：`xmyd0915/moonpkgconfig`；许可证：MIT。本版把参数分类、批量路径解释和大图修复提供给库使用者，保留既有解析、依赖检查及参数查询接口。

```sh
moon add xmyd0915/moonpkgconfig@0.2.0
```

## 新增接口

- `FlagResult::select(FlagSelection)`：分别取得头文件目录、其他编译参数、库目录、库参数或其他链接参数，保留来源、顺序和诊断。
- `PackageSet::dependency_paths` 与 `DependencyPaths::path_to`：一次建立前驱索引，按需生成最短依赖路径，支持私有边与虚拟包。
- CLI 新增五种 `--cflags-only-*`、`--libs-only-*` 查询，沿用 JSON、来源解释和路径策略。

## 修复与集成

依赖解析采用显式栈，修复5,000包长链的原生进程异常退出。解释多个参数时复用路径搜索；单次查询索引虚拟提供者并缓存依赖步骤；整目录检查复用能够证明无诊断、无冲突字段的有效子图。保持精确包优先、候选插入顺序、每根冲突范围和诊断顺序。

增加真实 zlib、libpng → zlib 的 MoonBit FFI 示例，包含安装元数据查询、静态链接参数、缺失私有依赖诊断、压缩/解压和 PNG 像素往返。原生库示例使用独立模块，核心库不增加外部 C 库依赖。

## 验证

- 78个逻辑测试分别在 wasm、wasm-gc、JavaScript、native 通过。
- 与固定 pkgconf 3.0.7 的38项输出/退出码差分通过，保留11个官方兼容样本。
- 26个大图、问题图和展开边界工作负载验证正确结果；耗时记录不设机器相关的 CI 门槛。
- 实际发布归档在独立工作区执行78项源码测试和3项外部消费者测试，四目标均成功。
- Windows 本地和 Ubuntu CI 检查源码、归档、CLI、C/C++ 与真实 zlib/libpng 集成。

性能数据及计时范围见 [路径测量](performance.md) 和 [查询测量](query-performance.md)。服务端发布、源码标签和下载复验结果由主分支的 [发布记录](release.md) 继续记录。

## 已知边界

仍不自动读取宿主 pkg-config 搜索环境，不实现完整片段优化或 Windows 自动重定位。文本参数按 POSIX shell 规则展示，跨平台程序集成应读取 JSON 数组。问题根、循环根及含冲突字段的根可能重复遍历共同子图，最坏情况仍有平方级开销。真实 FFI 示例目前未适配 Windows MSVC。
