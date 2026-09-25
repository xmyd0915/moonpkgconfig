# pkgconf 对照记录

最近复核：2026-09-25；平台：Windows x64 与 Ubuntu CI。

对照工具为 pkgconf 3.0.7 官方 Windows x64 MSI：

- 发布页：<https://github.com/pkgconf/pkgconf/releases/tag/pkgconf-3.0.7>
- 文件：`pkgconf-x64-3.0.7.msi`
- SHA-256：`7a316dba4a4498ea952b746c82deed41c597657095a0f776b75654191b45ae44`

安装包以管理映像方式解包到仓库忽略的 `.tools` 目录，没有把二进制文件提交进项目。

Ubuntu CI 从同一官方发布下载 `pkgconf-3.0.7.tar.xz`，校验 SHA-256 `c926ff491cbd9a331a589160811bd97ab1749b4d5198a519338f2cdfabe6940a` 后在临时目录编译。差分测试不使用发行版预装版本，避免参考语义随 runner 镜像变化。

## 对照样例

`examples/valid` 包含 `imagekit -> codec -> compression` 三个自编包。每个包都有独立的编译和链接参数，根包和依赖还包含私有链接字段。

pkgconf 查询结果：

```text
--modversion imagekit
1.2.0

--cflags imagekit
-I/opt/example/include -DIMAGEKIT=1 -I/opt/example/include/codec -I/opt/example/include/compression

--libs imagekit
-L/opt/example/lib -limagekit -lcodec -lcompression

--static --libs imagekit
-L/opt/example/lib -limagekit -lm -lcodec -lcompression -lz
```

MoonPkgConfig 查询结果：

```text
--cflags
-I/opt/example/include -DIMAGEKIT=1 -I/opt/example/include/codec -I/opt/example/include/compression

--libs
-L/opt/example/lib -limagekit -L/opt/example/lib -lcodec -L/opt/example/lib -lcompression

--libs --static
-L/opt/example/lib -limagekit -lm -L/opt/example/lib -lcodec -L/opt/example/lib -lcompression -lz

--libs --dedupe-paths
-L/opt/example/lib -limagekit -lcodec -lcompression

--libs --static --dedupe-paths
-L/opt/example/lib -limagekit -lm -lcodec -lcompression -lz
```

## 结论与差异

- 两边识别到相同的根包版本，并以相同顺序输出编译参数、动态链接库和静态私有库。
- MoonPkgConfig 默认保留每个包提供的重复 `-L`，便于解释来源；显式加入 `--dedupe-paths` 后，本样例的动态和静态链接输出与 pkgconf 一致。
- `examples/invalid/broken.pc` 会被两边拒绝。MoonPkgConfig 额外把未定义变量和空 `Name` 作为严格诊断；pkgconf 会裁剪带空白的版本，并报告缺失 `Description` 等问题。

`examples/order` 是一个带共享传递依赖的菱形图，根包同时具有公开和私有依赖。Cflags 查询会包含公开和私有依赖的编译参数，两边顺序均为 `root -> left -> right -> common`；动态 Libs 只使用公开边，静态 Libs 会加入私有边，两边静态顺序均为 `root -> root-private -> left -> right -> common`。这些断言同时在本地验证和CI中运行。

对 `imagekit` 执行 `--modversion`、`--exists`、最低版本1.1、精确版本1.2.0和最高版本1.1查询时，两边分别得到版本1.2.0以及退出码0、0、0、1；这些退出码也进入持续验证。

对 `imagekit` 执行 `--variable=prefix` 时，两边均输出 `/opt/example`；加入 `--define-variable=prefix=/custom` 后，变量查询均输出 `/custom`，Cflags 均改为 `/custom/include` 下的三组路径。变量读取、覆盖和覆盖后的参数展开已进入本地验证与 CI。

`examples/path-policy` 固定了 `/usr/include`、`/usr/lib` 与自定义目录。给 pkgconf 显式设置系统目录环境变量、给 MoonPkgConfig 传入对应的 `--system-include-path`/`--system-library-path` 后，两边都只移除精确匹配的 `-I`/`-L`；设置 `/sdk` sysroot 后，两边均重写绝对的 `-I`、`-L` 和 `-isystem` 路径。4项路径输出已加入差分，总比较数为20项。MoonPkgConfig 使用显式参数而非读取宿主环境，以保证构建复现性。

官方 `provides.pc` 声明了 `=、!=、<、<=、>、>=` 六种虚拟包范围。MoonPkgConfig 按 pkgconf 3.0.7 源码中的比较矩阵实现，而不是把两边约束简单视为区间相交。`bar-new` 对 `provides-test-bar >= 1.1.1` 的依赖在两边均成功，`bar-old` 对 `provides-test-bar <= 1.1.0` 的依赖在两边均失败；这两项退出码差分使总比较数增至22项。

这些差异是当前兼容边界，不把本次结果表述为完整兼容。搜索路径去重只处理连接式或分离式 `-I`/`-L`，不会删除重复库或其他可能影响链接语义的参数。系统目录仅精确匹配；sysroot 不自动读取环境。后续仍需扩大真实 `.pc` 文件样本，并继续核对参数顺序。

## 上游测试样本

仓库另包含11个未经修改的pkgconf 3.0.7官方测试文件，固定到提交 `0c9e506b64124d8727b68d8af0ed73739e66e2ba`。它们在Windows本地验证和Ubuntu CI中通过整目录检查，覆盖变量空白、续行、CRLF、无末尾换行、反斜杠、引号、美元转义、分离式参数和虚拟包范围等输入。

样本清单、原始路径与ISC许可证见 [`testdata/pkgconf-3.0.7`](../testdata/pkgconf-3.0.7)。这是选定语料的兼容证据，不等同于完整pkgconf一致性。
