# MoonPkgConfig 0.3.0 发行说明

模块名称：`xmyd0915/moonpkgconfig@0.3.0`；许可证：MIT。实际上传、源码标签和注册表下载安装结果见 [发布记录](release.md)。

本版补齐静态编译字段并扩大真实兼容性与集成证据。许可证仍为 MIT；核心不增加新的依赖，既有默认查询行为保持不变。

## 静态编译接口

`PackageSet::collect_cflags(root, static_linking=true)` 支持 pkgconf 扩展 `Cflags.private`。先按依赖查询顺序输出全部普通 `Cflags`，再按同一包顺序追加私有字段；保留参数所属包、字段、位置、诊断与分离式操作数边界。

CLI 的 `--cflags`、`--cflags-only-I` 和 `--cflags-only-other` 均可加 `--static`。默认 `collect_cflags(root)` 不加入该字段，公开与私有依赖的普通编译参数仍参与查询。

## 实际接入

增加真实 Expat 静态库的 MoonBit XML 解析示例。安装生成的 `.pc` 不作修改，静态编译参数提供 `XML_STATIC`；9次正常/分块解析、4类错误输入及4项 FFI 边界检查由 MoonBit 执行，并与 Python 独立安装的 XML 解析器核对。

Windows MSVC 另验证负对照：仅移除私有编译字段会产生 DLL 导入符号链接失败，恢复同一查询结果后构建和运行成功。该负对照不适用于 POSIX。真实构建、报告与范围见 [Expat 示例](../examples/expat-ffi/README.md)。

包含自0.2.0之后的 Windows zlib 集成及可复制的文件压缩消费者。该消费者仍固定使用已发布0.2.0，作为已有接口的实际使用基线；0.3.0另通过实际归档消费者验证新增接口。

## 兼容性与验证

- 81项核心逻辑测试分别在 wasm、wasm-gc、JavaScript、native 执行。
- 原38项 pkgconf 差分继续执行；六个固定版本真实模板的120项查询和4项静态字段顺序对照，使总数增至162项。
- 默认种子下64个有效参数输入和94个异常/截断输入检查参数、JSON、退出码、来源和确定性。
- 实际发行归档的公开接口消费者包含4项测试，覆盖新增静态编译字段；与81项归档源码测试一起在四目标执行。
- 保留真实 C/C++、zlib、libpng 接入，大图及展开边界检查；CI 上传兼容性和真实消费者报告。

以上数量是所覆盖范围的证据。固定模板、配置值、许可证哈希及输入重现见 [兼容性检查](compatibility.md)。注册表验证使用 `python scripts/verify-install.py --version 0.3.0`，在无本地源码覆盖的新模块中下载并检查公开接口；实际结果单独记入发布记录，不用归档验证替代。

## 边界

仍不处理 `Cflags.shared`、完整片段去重、全部 pkgconf 扩展或 Windows 自动重定位。系统搜索目录和 sysroot 均显式传入；文本展示使用 POSIX shell 规则，程序应读取参数数组。问题图的目录检查仍可能重复遍历。
