# 版本与发布记录

主分支的接入示例会继续更新。以下完成记录描述对应标签和上传归档中的内容；当前推荐模板使用已发布0.3.1，运行方式见 [原生接入指南](native-walkthrough.md)。

## 0.3.1 完成记录（2026-10-18）

`xmyd0915/moonpkgconfig@0.3.1` 已正式发布，上传器退出码0，服务端返回 `200 OK`；公开索引包含0.3.1且未撤回。本版保留损坏依赖的原始文件错误，新增可选诊断映射，范围见 [发行说明](release-notes-0.3.1.md)。

- [源码标签 v0.3.1](https://github.com/xmyd0915/moonpkgconfig/tree/v0.3.1) 固定到提交 `c138e4fc23291f4441eec9eabecd34a8b451243d`；[发行提交 CI](https://github.com/xmyd0915/moonpkgconfig/actions/runs/39070804193) 的 Ubuntu 与 Windows 检查全部成功。
- 最终上传归档在独立工作区通过89项源码测试和6项公开接口消费者测试，四目标各95项通过；从归档内另外执行22个文件加载场景。两个 CI 归档的源码内容与最终包一致，Windows CI ZIP 与上传 ZIP 字节完全一致。
- 上传后执行 `python scripts/verify-install.py --version 0.3.1 --report _build/verification/registry-install-0.3.1.json`，新项目从 MoonCakes 实际下载0.3.1，无本地源码覆盖；四目标检查和每目标6项消费者测试全部通过，包含新增诊断参数、私有模式和虚拟提供者路径行为。
- 实际上传 ZIP 与注册表索引的 SHA-256 一致：`6bf84a282251cba9cc3f8050f544aba01b0e63158017011ed9ca06c5b05c3387`。
- 发布预检由服务端确认 `202 Accepted`、成功且没有作出更改；旧上传器对此返回非零。正式发布以 `200 OK`、退出码0、注册表校验值及实际下载安装另行确认。

正式归档副本为 `_build/releases/xmyd0915-moonpkgconfig-0.3.1.zip`，机器记录为 `_build/verification/release-0.3.1.json`。最终发行只整理候选文档，代码与验收脚本保持候选提交的内容；候选包不作为实际上传包记录。既有0.1.0、0.2.0、0.3.0归档和标签保留。通用原生模板继续使用0.3.0，文件压缩消费者继续使用0.2.0，作为兼容性基线。

## 0.3.1 发行准备（2026-10-18）

根模块版本为0.3.1，修复损坏依赖被误报为缺包的问题，完整范围见 [发行说明](release-notes-0.3.1.md)。现有通用模板固定使用0.3.0，文件压缩消费者固定0.2.0。

发行验收使用 `python scripts/verify-install.py --package --report _build/verification/package-install.json`，从实际 ZIP 提取源码。Windows 本机四目标各通过89项源码测试和6项消费者测试，共95项，并从归档内执行22个文件加载场景；报告记录实际归档 SHA-256、版本和每条命令结果。双平台 CI 另保存报告与实际测试的 ZIP。准备完成后，候选归档及对应提交、校验值、CI 结果保存在 `_build/verification/release-candidate-0.3.1.json`。

候选提交 `e7b8258f57cffd4b6e3ba2222859251fe84225f5` 的 [双平台 CI](https://github.com/xmyd0915/moonpkgconfig/actions/runs/39034720203) 全部通过，已核对两平台实际 ZIP、测试报告及四目标各95项测试日志。正式发行文档整理后，再验收最终上传 ZIP；服务端上传、标签和注册表新项目安装结果在完成记录中追加。0.3.0正式归档及标签不覆盖。

## 0.3.0 完成记录（2026-10-17）

`xmyd0915/moonpkgconfig@0.3.0` 已正式发布，上传器退出码0，服务端返回 `200 OK`；公开索引包含0.3.0且未撤回。新增静态编译字段及真实 Expat 接入，范围见 [发行说明](release-notes-0.3.0.md)。既有0.1.0、0.2.0发行版本和标签保持原内容。

- [源码标签 v0.3.0](https://github.com/xmyd0915/moonpkgconfig/tree/v0.3.0) 固定到提交 `19aa710b356fa33406e9ed8345b3143d4022e77f`；[发行提交 CI](https://github.com/xmyd0915/moonpkgconfig/actions/runs/39032073532) 的 Ubuntu 与 Windows 检查全部成功。
- `python scripts/verify-install.py --package` 从实际上传归档提取源码，在独立工作区执行81项源码测试和4项公开接口消费者测试，四目标各85项通过。
- 正式上传后执行 `python scripts/verify-install.py --version 0.3.0`，全新模块实际从 MoonCakes 下载0.3.0，无本地源码覆盖；四目标检查和每目标4项消费者测试全部通过，含静态编译字段、分类、来源与依赖顺序。
- 上传器生成的 ZIP 与测试归档、注册表索引的 SHA-256 一致：`5c0523a0dc393aeca4d8dc75f8e08e6f98534450462a34e55ed5f6635d18a4ac`。
- 发布预检返回 `202 Accepted` 并确认未作修改，旧上传器对此返回非零；正式上传另以 `200 OK`、索引校验和真实下载安装确认完成。

复验旧0.2.0时应显式使用 `python scripts/verify-install.py --version 0.2.0`；独立 zlib 文件消费者继续固定该版本作为兼容性基线。正式归档副本保存于 `_build/releases/xmyd0915-moonpkgconfig-0.3.0.zip`，机器记录为 `_build/verification/release-0.3.0.json`；这些验证产物不纳入源码包。

## 0.2.0 发行内容

- 模块为 `xmyd0915/moonpkgconfig@0.2.0`，项目名称为 MoonPkgConfig，许可证为 MIT。
- 新增参数分类和批量路径接口，包含深链、查询及目录检查性能修复；完整范围见 [0.2.0发行说明](release-notes-0.2.0.md)。
- 核心78项四目标测试、38项固定工具差分和26个大图/边界工作负载用于本版验证；真实 C/C++、zlib 和 libpng 集成保留。
- `python scripts/verify-install.py --package` 从实际 ZIP 中提取源码，独立工作区运行公开接口消费者；该入口进入本地验证和 CI。
- `python scripts/verify-install.py` 在无本地源码覆盖的新模块中，从 MoonCakes 下载 `moon.mod` 所指定的版本并验证新增接口。
- 打包清单检查许可证、来源和新增核心文件，拒绝构建缓存、工具、临时目录、凭据文件及越界归档路径。

服务端发布结果、源码标签和下载安装复验在本页完成记录中持续维护；已上传的版本归档不重新覆盖。

## 0.2.0 完成记录（2026-10-17）

- 正式发布返回 `200 OK`，上传器退出码0；公开索引包含0.2.0，未撤回。
- [源码标签 v0.2.0](https://github.com/xmyd0915/moonpkgconfig/tree/v0.2.0) 固定到提交 `092d2fa40a5e834ca64ac3de44e679628d952f6e`；[发布前 CI](https://github.com/xmyd0915/moonpkgconfig/actions/runs/39004844362) 通过，含实际归档消费者、四目标回归、26个工作负载、38项差分及真实原生库集成。
- 新建无本地源码覆盖的消费者项目，实际下载 `xmyd0915/moonpkgconfig@0.2.0`，确认安装元数据版本，并通过 wasm、wasm-gc、JavaScript、native 四目标检查；3项公开接口消费者测试在每个目标均通过。
- 上传 ZIP 与公开索引的 SHA-256 一致：`396f375dfdda252c8551b0376a7beb962f72e1ddcde732b3a15679aa3056d5fb`。
- 预检时服务端返回 `202 Accepted` 并明确确认未作更改，旧版上传器对此返回非零退出码；正式发布另以 `200 OK`、公开索引和真实下载安装完成确认。

## 0.1.0 首次发布记录

- 模块版本为 `0.1.0`，许可证为 MIT，仓库地址已写入 `moon.mod`。
- `moon package --list` 已进入本地验证与 CI，必须包含核心源码、README、许可证和来源说明，且不能包含构建目录、工具缓存或登录凭据。
- 核心库和命令行工具均通过四目标检查；原生 CLI 在 Windows 与 Ubuntu 验证。Windows 本地验证使用 `moonc 0.10.14`。
- 模块名已由开发期占位名改为 `xmyd0915/moonpkgconfig`，0.1.0 已发布到 [MoonCakes](https://mooncakes.io/docs/xmyd0915/moonpkgconfig)。
- 命名空间变更后，完整本地验证及 MoonCakes 发布预检通过；正式发布返回 `200 OK`，公开页面可访问。

## 一致性审计（2026-09-25）

| 项目事实 | 核对结果 |
| --- | --- |
| 项目名称与仓库 | MoonPkgConfig；仓库地址与 `moon.mod` 一致 |
| 主要语言与方向 | MoonBit；语言与开发工具、FFI及构建集成方向 |
| 原创与参考 | 独立实现；参考来源、固定版本、样本路径及许可证已记录 |
| 项目许可证 | MIT；上游样本分别保留原许可证 |
| 当前验证数字 | 59个逻辑测试、11个官方样本、22项固定版本差分 |
| 对外声明边界 | 不宣称完整替代pkg-config/pkgconf；MoonCakes 上为 0.1.0 版本 |


## 后续维护

后续如修改公开 API 或行为，先增加测试并更新 `CHANGELOG.md`，通过四目标与原生集成验证后再按语义化版本递增发布。登录凭据不得进入仓库或验证记录。

GitHub Release 可在需要独立发布公告或归档时再创建，不影响 MoonCakes 0.1.0 的安装。
