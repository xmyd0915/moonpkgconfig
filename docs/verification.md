# 验证记录

最近验证：2026-10-17；核心回归平台：Windows x64 与 Ubuntu CI；真实 zlib、Expat FFI 平台：Ubuntu CI 与 Windows x64 MSVC；libpng FFI 平台：Ubuntu CI。

工具链：`moon 0.1.20260915 (2e1a46d 2026-09-15)`，`moonc v0.10.14+7d59c7ec9 (2026-09-18)`。

当前主分支增加损坏依赖诊断修复，尚未发布。89项核心测试与22个文件加载场景通过；两个通用模板消费者实际使用 MoonCakes 0.3.0，保持发行版本和开发版本的证据分开。

通过 `scripts/verify.ps1` 执行：

| 检查 | 结果 |
| --- | --- |
| `moon fmt` | 成功 |
| `moon check --target all --deny-warn` | 四目标成功，无警告 |
| `moon test --target all --deny-warn` | 主分支 wasm 89/89，wasm-gc 89/89，JS 89/89，native 89/89；0.3.0发行源码仍为81项 |
| 损坏依赖原始错误 | 新增8项核心回归与22个文件加载 CLI 场景；验证原始文件/行列、静态私有模式、同名目录优先级、虚拟提供者、共享失败去重、版本失败的不可达子图及修复后重新加载。报告为 `_build/verification/load-diagnostics.json` |
| 0.3.0通用模板 | zlib、Expat 应用在仓库外分别验证缺失/版本失败与修复后构建运行；规划器及构建适配代码相同，参数指向实际安装。zlib 含空格路径、CRC-32、3次往返及3类错误；Expat 的13个解析结果由独立 Python 安装核对，另通过4项 FFI 边界检查。Windows 另验证未知适配选项被拒绝，报告为 `_build/verification/native-consumer-*.json` |
| `moon run cmd/demo` | 成功，输出六项字段及来源，无解析诊断 |
| `scripts/review-demo.*` | 来源解释、错误目录、sysroot与虚拟包范围四步演示均通过；成功/失败退出码均有断言 |
| `moon package --list` | 成功，包含核心源码、README、许可证与来源说明，不包含构建、工具或凭据文件 |
| 0.2.0 发布归档消费者 | 实际 ZIP 包含分类、路径、查询上下文与目录检查源码；在独立工作区四目标执行78项归档源码测试和3项消费者测试，验证公开 API 可导入并运行 |
| 0.3.0发行归档消费者 | 实际上传归档在独立工作区四目标执行81项源码测试和4项消费者测试，每目标85项通过；新增消费者直接导入并检查静态编译字段、依赖顺序及来源。已发布0.2.0归档保持原内容 |
| MoonCakes 0.1.0 历史复验 | 2026-09-28：`xmyd0915/moonpkgconfig@0.1.0` 可在全新临时模块中下载并通过 `moon check --target all --deny-warn` |
| MoonCakes 0.2.0 安装复验 | 2026-10-17：正式发布返回 `200 OK`；全新模块实际下载0.2.0，无本地源码覆盖，四目标检查和每目标3项公开接口消费者测试均通过；归档 SHA-256 与公开索引一致 |
| MoonCakes 0.3.0 安装复验 | 2026-10-17：正式发布返回 `200 OK`、退出码0；全新模块实际下载0.3.0，无本地源码覆盖，四目标检查和每目标4项公开接口消费者测试通过；含静态编译字段、依赖顺序和来源。上传 ZIP、测试归档与注册表索引 SHA-256 一致，源码标签为 `v0.3.0` |
| `moon run --target native cmd/inspect examples/valid/imagekit.pc` | 成功，从磁盘读取并输出九项字段及来源，无解析诊断 |
| `moon run --target native cmd/inspect examples/valid/imagekit.pc --json` | 成功，输出完整条目与空诊断数组 |
| `moon run --target native cmd/inspect examples/invalid/broken.pc` | 按预期报告五项问题并返回退出码 1 |
| `cmd/query` 三种查询 | Cflags、动态 Libs、静态 Libs 均成功并通过精确输出断言 |
| `cmd/query` 五种参数分类 | 包含头文件目录、其他编译选项、库目录、库及其他链接选项；CLI 检查 JSON、来源解释、静态私有参数、带空格/分离式参数及错误退出码；GNU 链接器分组保持完整 |
| `cmd/query --dedupe-paths` | 连接式与分离式重复搜索路径按同一路径稳定去除；孤立选项不会跨包或字段绑定下一参数 |
| `cmd/query` 路径策略 | 显式系统目录过滤与 sysroot 重写通过精确输出断言；连接式/分离式参数均保留来源 |
| `cmd/query` 虚拟包范围 | 官方 `provides.pc` 的六种运算符按 pkgconf 3.0.7 比较矩阵解析；匹配与拒绝样例退出码一致 |
| `cmd/query` 参数引用 | 官方 `fragment-quoting.pc` 中含字面引号的宏参数按 POSIX shell 规则输出，并通过精确断言 |
| `cmd/query` 参数顺序 | 菱形依赖中 Cflags 包含公开/私有依赖，动态 Libs 只含公开依赖，静态 Libs 加入私有依赖；顺序与 pkgconf 3.0.7 一致 |
| `cmd/query --explain` | 每个参数显示包、字段、源码位置及从根包出发的最短公开/私有依赖路径 |
| 大图与边界工作负载 | 1,000包的长链、宽图、共享叶子和虚拟包图分别检查解析/参数/路径/整目录；5,000包长链检查解析、链尾路径及整目录；1,000包缺失依赖长链精确保留一条 `PC015`；6种展开边界按长度成功或返回 `PC009`。耗时仅记录，不作 CI 速度门槛 |
| 路径快照与深图回归 | 前驱索引保留最短路径、声明顺序、私有边、虚拟包和快照语义；5,000包长链四目标均通过，循环及独立错误的诊断顺序保持一致 |
| 原生性能测量 | Windows native release 的四种图、三种规模、六种操作各3次，另有深链及展开边界记录；范围、原始采样和剩余瓶颈见 [性能报告](performance.md) |
| 查询与目录优化 | 单次查询复用提供者候选和依赖步骤，有效子图复用检查判定；精确名优先、候选顺序、文档修改可见性、每根冲突集合及错误顺序通过回归。2026-10-17同机前后采样、内存变化和问题图边界见 [查询性能报告](query-performance.md) |
| `cmd/query` 查询隔离 | 同目录存在无关损坏文件时正常包仍可查询；直接查询损坏包会返回其原始诊断和退出码 1 |
| `cmd/query --json` 失败结果 | 损坏目标包仍输出可解析的 `flags`、`diagnostics` 对象，诊断为 `PC004`，退出码 1 |
| `cmd/query --path` | 首目录中的同名包获胜，后续目录可补足依赖；反转目录顺序会按预期改变选中版本 |
| `cmd/query` 元数据模式 | 版本输出、存在性、最低/最高/精确版本条件的输出及退出码与 pkgconf 3.0.7 对照一致 |
| `cmd/query` 变量模式 | 变量读取、调用方覆盖及覆盖后的依赖参数展开与 pkgconf 3.0.7 对照一致 |
| `cmd/check examples/valid` | 成功，检查 3 个包、0 项诊断，退出码 0 |
| `cmd/check examples/invalid` | 报告解析及公开/私有依赖问题，共 4 项诊断，退出码 1 |
| `cmd/check testdata/pkgconf-3.0.7` | 11个未经修改的官方pkgconf 3.0.7样本全部通过，退出码 0 |
| 原生 C/C++ 闭环 | 查询 `moonpkg-demo.pc` 得到参数，编译 C 静态库与 C++ 调用程序，运行输出精确匹配 |
| 真实 MoonBit zlib FFI | 从官方 zlib 1.3.1 发行包构建静态库，查询安装生成的 `zlib.pc` 并生成 MoonBit 原生配置；标准 CRC-32 向量、3种输入的压缩/解压及3种错误返回在 Ubuntu CI 和本机 Windows x64 MSVC 全部通过 |
| Windows zlib 安装与空格路径 | MSVC 14.51.36231、Windows SDK 10.0.28000.0、CMake 3.31.8；校验固定归档后以 `/MT` 构建安装，显式映射 `-lz` 到 `zlibstatic.lib`。原始安装及更新前缀、正确引用路径的独立副本均成功；同一命令接入 Windows CI |
| MSVC 示例适配边界 | 8项 Python 检查通过：连接/分离参数、引号与反斜线、库名映射和顺序、空结果、未知选项、缺失操作数、跨来源隔离与不支持的库名写法。检查属于示例构建脚本，核心仍返回原始参数 |
| 发布包文件工具消费者 | 自包含目录复制到仓库外，实际导入 MoonCakes 0.2.0 及文件适配接口；`PC015`、`PC016` 均定位到应用依赖声明第4行。修复后使用安装生成的 zlib 参数构建文件工具，空文件、文本、512 KiB 二进制往返及 Python zlib 双向互操作通过；损坏输入不生成结果，已有输出保持原内容。Windows 本机正确引用的空格库路径通过，同一流程接入双平台 CI |
| 真实私有依赖与 PNG | 官方 libpng 1.6.59 与 zlib 1.3.1 分别静态安装到不同前缀；查询普通/静态参数，验证缺失私有依赖时的退出码及 `PC015`，并在 MoonBit 中完成3组 RGBA PNG 像素往返和4种错误检查。当前示例未适配 Windows MSVC |
| 真实 Expat 静态编译 | 官方2.6.2发行包经固定 SHA-256 校验，由 CMake 构建静态库；安装元数据不改写。静态查询提供 `XML_STATIC`，MoonBit 完成9次正常/分块解析、4类错误输入及4项边界检查，Python独立安装核对计数、状态、错误和位置。MSVC 移除该私有字段复现 `__imp_XML_*` 链接失败，恢复后成功；报告为 `_build/verification/expat.json`，流程接入 Ubuntu 与 Windows CI |
| `cmd/check testdata/real-world` | zlib 1.3.1 与 libffi 3.4.6 固定上游模板全部通过，退出码 0 |
| 自动 pkgconf 差分 | 38 项 Cflags、动态/静态 Libs、五种参数分类、依赖顺序、路径策略、虚拟包、真实模板、版本、变量覆盖及退出码与固定的 pkgconf 3.0.7 一致；仅忽略行末空白差异 |
| 六项目模板差分与独立预期 | 六个固定提交的上游模板与完整许可证通过 SHA-256 校验；120项配置查询和4项跨包静态顺序与声明预期、pkgconf 3.0.7 一致，参数来源指回对应字段。包含0.3.0的 Expat `Cflags.private` 修复；原38项差分继续执行 |
| 固定种子输入检查 | 种子20261017：64个有效参数输入通过 Python shlex 参数数组与展示往返对照，含 CRLF/BOM/无末尾换行；94个异常/截断输入通过文件、静态编译和静态链接查询的 JSON/退出码/来源检查及抽样确定性检查，单进程20秒超时即失败。完整报告与输入保留于忽略目录 |
| GitHub Actions CI | 2026-10-17：0.2.0发行提交 `092d2fa` 在固定工具链的 Ubuntu 全新环境成功，含78个四目标核心测试、实际归档源码和3项消费者测试、分类 CLI 检查、26个大图/展开边界工作负载、评审演示、包内容检查、C/C++ 闭环、真实 zlib/libpng FFI、11个上游样本及38项固定版本差分；运行记录：[39004844362](https://github.com/xmyd0915/moonpkgconfig/actions/runs/39004844362)。9月首次发布的运行记录保留于 [36442570605](https://github.com/xmyd0915/moonpkgconfig/actions/runs/36442570605) |

主分支89个逻辑测试在四个目标各运行一次，按逻辑测试计数。覆盖顺序变量展开、调用方变量覆盖、未定义/自引用、字面美元符、命名空间与大小写、重复/保留定义、BOM/CRLF/注释/续行/Unicode、字段和值位置、包元数据校验、直接与传递依赖检查、全包检查去重及有效子图复用、最短公开/私有依赖路径和快照、5,000包深链/目录及诊断顺序、查询缓存刷新、精确包优先和虚拟候选顺序、损坏依赖原始诊断及共享失败去重、Cflags 私有依赖及静态私有字段语义、虚拟包范围比较矩阵、循环和每根独立包冲突诊断、参数聚合与来源、五种参数分类及 GNU 链接器分组、稳定的菱形依赖顺序、POSIX shell 参数边界、跨写法搜索路径去重、系统目录过滤、sysroot重写和来源边界、JSON 输出、参数引号/转义、版本分段比较、六种约束运算符及错误恢复、展开大小上限。

当前证据仅证明所覆盖子集。目录、系统路径和sysroot均由调用者显式指定，不读取宿主pkg-config环境；参数结果对照使用自编依赖图及六项目模板的明确配置副本，上游语料另包含11个固定的pkgconf官方测试文件。完整配置、种子与重现方式见 [兼容性检查](compatibility.md)。

独立文件消费者的机器可读报告保存于 `_build/verification/zlib-consumer.json`；双平台 CI 分别上传 `ubuntu-published-consumer` 和 `windows-published-consumer` 附件，包含两种失败诊断、修复后的参数来源、依赖路径和文件摘要。

## 对照工具与记录

0.3.0候选提交 `c372debb81b5a4b7447bc5a78d16bdbb7101b9ba` 的双平台 [CI 39025581516](https://github.com/xmyd0915/moonpkgconfig/actions/runs/39025581516) 成功：Ubuntu 包含81项四目标核心测试、4项四目标归档消费者测试、162项固定 pkgconf 差分、158个生成输入、真实 C/C++、zlib、libpng 和 Expat；Windows 通过 zlib、发布包文件消费者及 Expat 正/负对照。附件包含 `ubuntu-expat`、`windows-expat` 及既有兼容性和消费者报告。此为发布前候选验证记录。

正式发行提交 `19aa710b356fa33406e9ed8345b3143d4022e77f` 的双平台 [CI 39032073532](https://github.com/xmyd0915/moonpkgconfig/actions/runs/39032073532) 同样通过。0.3.0上传、标签、注册表下载安装和归档校验值见 [发布记录](release.md)。

已下载并校验官方 pkgconf 3.0.7 Windows x64 MSI，发布资产 SHA-256 为 `7a316dba4a4498ea952b746c82deed41c597657095a0f776b75654191b45ae44`。对照结果和已知差异见 `docs/pkgconf-comparison.md`。

后续开发保持可追踪的提交记录。月度资格审核和最终验收由主办方决定。
