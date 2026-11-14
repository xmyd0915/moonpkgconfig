# 独立命令行下载与校验

独立命令行包解压后即可运行，不需要安装 MoonBit 工具链。模块版本、源码提交号、平台和工具链都记录在包内的 `build-info.json` 中。

## 下载

正式版本从 [GitHub Releases](https://github.com/xmyd0915/moonpkgconfig/releases) 下载对应系统的 ZIP 和同名 `.sha256` 文件，再按下文校验。发行附件保留原始构建提交号，可与标签和 CI 核对。核心库则通过 `moon add xmyd0915/moonpkgconfig@0.4.0` 安装。

主分支的最新开发构建仍可从 Actions 获取：

1. 打开 [CI 工作流](https://github.com/xmyd0915/moonpkgconfig/actions/workflows/ci.yml)，选择目标提交且整体成功的运行。
2. 在 Artifacts 中下载 `ubuntu-cli-package` 或 `windows-cli-package`。
3. 解开 GitHub 附件的外层归档，找到命令行 ZIP、对应的 `.sha256` 文件和 `cli-package.json` 验证报告。
4. 核对报告的 `passed` 及构建信息的源码提交号，再校验并解压命令行 ZIP。

下载 Actions 附件需要登录有仓库读取权限的 GitHub 账户，具体操作见 [GitHub 官方说明](https://docs.github.com/en/actions/how-tos/manage-workflow-runs/download-workflow-artifacts)。本工作流将开发构建保留30天；正式发行附件在 Releases 中单独保留。Actions 构建本身不代表发布了新的 MoonCakes 版本。

Ubuntu 包仅在对应 CI Ubuntu 环境与架构验证，不承诺兼容任意 Linux 发行版、旧版 glibc、macOS 或其他架构。Windows 包同样以构建信息记录的平台和架构为准。

## 校验与运行

Linux 在放有 ZIP 和同名校验文件的目录运行：

```sh
sha256sum -c moonpkgconfig-*.zip.sha256
unzip moonpkgconfig-*.zip -d moonpkgconfig-cli
chmod +x moonpkgconfig-cli/moonpkgconfig
./moonpkgconfig-cli/moonpkgconfig --help
./moonpkgconfig-cli/moonpkgconfig --version
```

Windows PowerShell 中选择下载得到的实际 ZIP；若目录有多份，请先移走无关文件或直接指定文件名：

```powershell
$package = Get-Item .\moonpkgconfig-*.zip
if (@($package).Count -ne 1) { throw 'Select exactly one CLI ZIP.' }
$expected = ((Get-Content -LiteralPath ($package.FullName + '.sha256')).Trim() -split '\s+')[0]
if ((Get-FileHash -LiteralPath $package.FullName -Algorithm SHA256).Hash -ne $expected) {
    throw 'CLI archive checksum mismatch.'
}
Expand-Archive -LiteralPath $package.FullName -DestinationPath .\moonpkgconfig-cli
.\moonpkgconfig-cli\moonpkgconfig.exe --help
```

包内包含标准名称的 `moonpkgconfig` 或 `moonpkgconfig.exe`、`LICENSE`、`THIRD-PARTY-NOTICES.txt`、`USAGE.txt`、`build-info.json` 和 `SHA256SUMS`。构建信息包括完整源码提交号、是否存在未提交改动、实际工具链版本、系统和架构；CI 要求干净源码。校验和用于发现文件变化，不是数字签名。

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

复现构建请使用 `moonc 0.10.20+65efd5b93`、`moon 0.1.20261104`。安装目录需要加入 PATH，也可使用 `moon install ./cmd/moonpkgconfig --bin <目录>`。

维护者使用 `python scripts/package-cli.py` 生成并验证独立包；CI 加 `--require-clean` 拒绝未提交源码。验证从实际 ZIP 解压到仓库之外的带空格目录，检查内容与哈希，清除 MoonBit 环境和 PATH 后执行命令、诊断及读取错误场景。源码安装仍需要工具链；已解压的命令行运行不调用 MoonBit 编译器。
