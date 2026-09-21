# pkgconf 对照记录

日期：2026-09-18；平台：Windows x64。

对照工具为 pkgconf 3.0.7 官方 Windows x64 MSI：

- 发布页：<https://github.com/pkgconf/pkgconf/releases/tag/pkgconf-3.0.7>
- 文件：`pkgconf-x64-3.0.7.msi`
- SHA-256：`7a316dba4a4498ea952b746c82deed41c597657095a0f776b75654191b45ae44`

安装包以管理映像方式解包到仓库忽略的 `.tools` 目录，没有把二进制文件提交进项目。

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
-I/opt/example/include/compression -I/opt/example/include/codec -I/opt/example/include -DIMAGEKIT=1

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

- 两边识别到相同的根包版本、编译参数集合、动态链接库集合和静态私有库集合。
- MoonPkgConfig 默认保留每个包提供的重复 `-L`，便于解释来源；显式加入 `--dedupe-paths` 后，本样例的动态和静态链接输出与 pkgconf 一致。
- MoonPkgConfig 当前以依赖优先顺序输出 Cflags；pkgconf 3.0.7 在该样例中以根包优先顺序输出。
- `examples/invalid/broken.pc` 会被两边拒绝。MoonPkgConfig 额外把未定义变量和空 `Name` 作为严格诊断；pkgconf 会裁剪带空白的版本，并报告缺失 `Description` 等问题。

这些差异是当前兼容边界，不把本次结果表述为完整兼容。搜索路径去重只处理连接式或分离式 `-I`/`-L`，不会删除重复库或其他可能影响链接语义的参数。后续仍需扩大真实 `.pc` 文件样本，并继续核对参数顺序。

## 上游测试样本

仓库另包含10个未经修改的pkgconf 3.0.7官方测试文件，固定到提交 `0c9e506b64124d8727b68d8af0ed73739e66e2ba`。它们在Windows本地验证和Ubuntu CI中通过整目录检查，覆盖变量空白、续行、CRLF、无末尾换行、反斜杠、引号、美元转义和分离式参数等输入。

样本清单、原始路径与ISC许可证见 [`testdata/pkgconf-3.0.7`](../testdata/pkgconf-3.0.7)。这是选定语料的兼容证据，不等同于完整pkgconf一致性。
