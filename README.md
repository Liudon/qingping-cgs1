# 青萍空气检测仪 CGS1 自定义页面

这是一次针对**初代青萍空气检测仪（CGS1）**的非官方界面改造实验。

设备运行嵌入式 Linux，官方界面程序 `SnowApp` 使用 Qt/QML。本项目通过分析并修改 `SnowApp` 内嵌的 Qt 资源，在**保留官方界面和传感器读数**的基础上，增加一个从外部 QML 文件加载的自定义页面。无需更换整套系统，也不需要重新编译固件。

> **适用范围**：目前仅在一台 CGS1、固件版本 `4.1.8_0287` 上验证过补丁版界面的运行。不同型号或固件版本的二进制结构可能不同，**不要直接套用仓库中的补丁程序**。

## 效果与功能

- 在官方滑动界面中增加一页自定义内容，原有页面仍可使用。
- 复用 `SnowApp` 暴露给 QML 的传感器数据，实时显示 CO₂、TVOC、PM2.5、温度、湿度和舒适度。
- 可选地从自建 HTTP 服务拉取 JSON，在页面下方显示标题与文本。
- 自定义页面放在 `/data/custom/CustomView.qml`；修改页面内容时无需再次修改 `SnowApp` 二进制。

目前是一个**最小可用的改造示例**，不是适配所有青萍设备的通用固件，也不是完整的刷机或救砖工具。

## 仓库文件

| 文件 | 作用 |
| --- | --- |
| [`CustomView.qml`](CustomView.qml) | 自定义界面，显示传感器数据和可选的远程文本 |
| [`env.sh`](env.sh) | 设备上独立运行 QML 时使用的 Qt/EGLFS 环境变量 |
| [`qrc_dump.py`](qrc_dump.py) | 从带有 Qt 资源符号的 ELF 中提取 QRC 文件，并生成 `INDEX.tsv` |
| [`qrc_patch.py`](qrc_patch.py) | 根据索引，原位替换 ELF 中的一个 Qt 资源 |
| [`SnowApp.patched`](SnowApp.patched) | 针对上述固件版本制作的实验性补丁程序 |
| [`install_patched.sh`](install_patched.sh) | 校验版本和 SHA-256、备份原版并安装补丁程序 |

## 实现思路

1. 通过设备的开发者选项开启 ADB，进入 CGS1 的 Linux 系统。
2. 分析 `SnowApp` 中的 `qt_resource_struct`、`qt_resource_name` 和 `qt_resource_data`，提取官方 QML。
3. 找到 `Main/MainPage.qml` 中由 `ListModel` 驱动的页面列表，增加一个 `ListElement`，指向 `file:///data/custom/CustomView.qml`。
4. 把修改后的 QML 重新压缩并**原位写回** ELF；保持其他资源的偏移量和文件整体大小不变。
5. 让官方 `SnowApp` 加载外置页面，继续使用原有的触控、页面切换和传感器数据接口。

原位替换有一个重要限制：**新资源必须能够放进旧资源的存储空间**。如果压缩后的内容太大，`qrc_patch.py` 会拒绝写入。这个工具不是通用 ELF 重打包器。

## 自定义页面

将 [`CustomView.qml`](CustomView.qml) 放到设备上的 `/data/custom/CustomView.qml`。

默认页面直接使用官方传感器数据，不需要额外配置。若希望显示来自自己服务器的文本，可修改文件中的：

```qml
property string serverUrl: "http://192.168.1.10:8000/board.json"
property int refreshSeconds: 10
```

接口返回示例：

```json
{
  "title": "家庭状态",
  "lines": ["客厅窗户已关闭", "洗衣机运行中", "今日待办 2 项"]
}
```

`serverUrl` 留空时不会发起请求。修改 `CustomView.qml` 后，需要重新启动 `SnowApp`（或重启设备）才能加载新内容。

## 重新制作补丁（开发者）

以下操作建议在 **Linux + Python 3 + GNU binutils（`nm`、`readelf`）** 环境中进行。需要先从**自己的设备**获取原版 `SnowApp`，并保留备份。

```bash
# 提取 Qt 资源及索引
python3 qrc_dump.py SnowApp out/

# 根据提取出的 Main/MainPage.qml 制作 MainPage.new.qml：
# 在主页 ListModel 中增加加载 /data/custom/CustomView.qml 的页面项
# 注意控制压缩后的体积，不得超过原资源槽位

# 生成补丁版程序
python3 qrc_patch.py SnowApp out/INDEX.tsv /Main/MainPage.qml MainPage.new.qml SnowApp.patched
```

需要新增的页面项：

```qml
ListElement {
    name: "customView"
    source: "file:///data/custom/CustomView.qml"
}
```

补丁生成后，应至少核对文件大小、重新解包结果及其他资源的哈希，再考虑上设备测试。仓库中的 `install_patched.sh` 包含**针对特定原版和补丁文件的固定 SHA-256**，不能直接用于其他固件生成的文件。

## 安装与恢复注意事项

本项目涉及 root 权限及设备原厂可执行文件，错误操作可能导致界面无法启动或设备反复重启。建议先确认 ADB 可用，完整备份 `/data`，并准备可行的恢复手段。

[`install_patched.sh`](install_patched.sh) 的设计前提是：设备保持正常运行、官方看门狗没有被停掉，并且以下文件已经传输到设备：

- `/data/custom/SnowApp.patched`
- `/data/custom/CustomView.qml`
- `/data/custom/install_patched.sh`

校验无误后，才在**设备的 root shell** 中运行：

```sh
sh /data/custom/install_patched.sh
```

脚本会核对原版与补丁版的哈希，保存原版到 `/data/custom/SnowApp.orig`，再替换 `/data/bin/SnowApp`。如果哈希不匹配，应停止操作，不要跳过检查。

需要恢复时，先确认 `/data/custom/SnowApp.orig` 是完整的原版备份，再在设备上执行：

```sh
cp /data/custom/SnowApp.orig /data/bin/SnowApp.new
chmod 755 /data/bin/SnowApp.new
mv -f /data/bin/SnowApp.new /data/bin/SnowApp
reboot
```

**注意**：如果补丁程序启动失败，看门狗可能反复尝试启动甚至强制重启；不能假设一定能在重启间隙通过 ADB 救回设备。官方升级也可能覆盖修改，升级后需要重新分析对应版本。

## 验证范围

在 CGS1（`4.1.8_0287`）上，已验证补丁版 `SnowApp` 能够手动启动，官方界面正常显示，新增第四页可以滑动进入，传感器读数能够实时刷新。

其他固件版本、长期稳定性及故障恢复路径未作为通用能力验证。请在自己的设备上谨慎测试。

---

这是个人硬件折腾记录，仅供学习和交流。设备及官方软件相关权利归其各自权利人所有，使用和分发时请自行确认相应许可与风险。
