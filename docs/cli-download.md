# 独立命令行下载与校验

独立命令行包解压后即可运行，不需要安装 MoonBit 工具链。模块版本、源码提交号、平台和工具链都记录在包内的 `build-info.json` 中。

## 下载

在 [0.4.1 发行页](https://github.com/xmyd0915/moonpkgconfig/releases/tag/v0.4.1) 选择下表中适合系统的 CLI ZIP，同时下载同名 `.zip.sha256` 校验文件。0.4.1 的构建工具链为 `moonc 0.10.21+06da1ed44` 和 `moon 0.1.20261117`。MoonBit 项目可通过 `moon add xmyd0915/moonpkgconfig@0.4.1` 安装核心库。

| 平台 | CLI ZIP |
| --- | --- |
| Linux x86_64（Ubuntu CI） | `moonpkgconfig-0.4.1-linux-x86_64.zip` |
| Windows x86_64 | `moonpkgconfig-0.4.1-windows-x86_64.zip` |

主分支的最新开发构建仍可从 Actions 获取：

1. 打开 [CI 工作流](https://github.com/xmyd0915/moonpkgconfig/actions/workflows/ci.yml)，选择目标提交且整体成功的运行。
2. 在 Artifacts 中下载 `ubuntu-cli-package` 或 `windows-cli-package`。
3. 解开 GitHub 附件的外层归档，找到命令行 ZIP、对应的 `.sha256` 文件和 `cli-package.json` 验证报告。
4. 核对报告的 `passed` 及构建信息的源码提交号，再校验并解压命令行 ZIP。

下载 Actions 附件需要登录有仓库读取权限的 GitHub 账户，具体操作见 [GitHub 官方说明](https://docs.github.com/en/actions/how-tos/manage-workflow-runs/download-workflow-artifacts)。本工作流将开发构建保留30天；正式发行附件在 Releases 中单独保留。Actions 构建本身不代表发布了新的 MoonCakes 版本。

Ubuntu 包仅在对应 CI Ubuntu 环境与架构验证，不承诺兼容任意 Linux 发行版、旧版 glibc、macOS 或其他架构。Windows 包同样以构建信息记录的平台和架构为准。

## 校验与运行

Linux 在放有 ZIP 和校验文件的目录运行以下命令。校验成功后再解压到新目录。

```sh
archive=moonpkgconfig-0.4.1-linux-x86_64.zip
sha256sum -c "$archive.sha256" &&
  unzip "$archive" -d moonpkgconfig-cli &&
  chmod +x moonpkgconfig-cli/moonpkgconfig &&
  ./moonpkgconfig-cli/moonpkgconfig --version
```

Windows PowerShell 在下载目录运行以下命令。

```powershell
$package = Get-Item -LiteralPath .\moonpkgconfig-0.4.1-windows-x86_64.zip -ErrorAction Stop
$expected = ((Get-Content -LiteralPath ($package.FullName + '.sha256')).Trim() -split '\s+')[0]
if ((Get-FileHash -LiteralPath $package.FullName -Algorithm SHA256).Hash -ne $expected) {
    throw 'CLI archive checksum mismatch.'
}
Expand-Archive -LiteralPath $package.FullName -DestinationPath .\moonpkgconfig-cli -ErrorAction Stop
.\moonpkgconfig-cli\moonpkgconfig.exe --version
```

两个平台的 0.4.1 发行包均输出 `moonpkgconfig 0.4.1`。校验开发构建时，将上方文件名替换为所下载的 CLI ZIP 名称。包内包含可执行文件、`LICENSE`、`THIRD-PARTY-NOTICES.txt`、`USAGE.txt`、`build-info.json` 和 `SHA256SUMS`。构建信息记录完整源码提交号、工作区状态、实际工具链版本、系统和架构。

在可执行文件目录中，可使用自己的 `.pc` 文件和目录：

```sh
./moonpkgconfig inspect /path/to/example.pc --json
./moonpkgconfig query /path/to/pkgconfig example --libs --static --json --explain
./moonpkgconfig check /path/to/pkgconfig --json
```

Windows 将开头的 `./moonpkgconfig` 换成 `.\moonpkgconfig.exe`，并使用实际目录。路径包含空格时引用整个路径。目录搜索顺序和机器输出契约见 [CLI JSON 接口](cli-json.md)。

## 从源码构建

```sh
git clone https://github.com/xmyd0915/moonpkgconfig.git
cd moonpkgconfig
moon update
moon install ./cmd/moonpkgconfig
```

主分支使用 `moonc 0.10.21+06da1ed44` 和 `moon 0.1.20261117`。复现 0.4.1 标签时，在 `moon update` 前执行 `git switch --detach v0.4.1`，使用上文所列的发行工具链。安装目录需要加入 PATH，也可使用 `moon install ./cmd/moonpkgconfig --bin <目录>`。

维护者使用 `python scripts/package-cli.py` 生成并验证独立包；CI 加 `--require-clean` 拒绝未提交源码。验证从实际 ZIP 解压到仓库之外的带空格目录，检查内容与哈希，清除 MoonBit 环境和 PATH 后执行命令、诊断及读取错误场景。源码安装仍需要工具链；已解压的命令行运行不调用 MoonBit 编译器。
