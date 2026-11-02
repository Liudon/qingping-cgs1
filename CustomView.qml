import QtQuick 2.9

// 自定义页，作为官方界面的最后一页。
// 设备上的位置：/data/custom/CustomView.qml
// 这个文件是 SnowApp 在启动时加载的，改完重启 SnowApp（或整机重启）即可生效，不需要再改 SnowApp。
Item {
    id: page
    implicitWidth: 720
    implicitHeight: 720

    // 可选：从你的服务器取一段文字显示在下方。留空则不联网。
    // 例："http://192.168.1.10:8000/board.json"
    // 返回格式：{"title":"标题","lines":["第一行","第二行","第三行"]}
    property string serverUrl: ""
    property int refreshSeconds: 10

    property string boardTitle: ""
    property var boardLines: []
    property string boardStatus: ""

    readonly property string textFont: "Roboto, Helvetica Neue, Source Han Sans CN"
    readonly property string numFont: "DIN Condensed"

    // MainPage 在每次滑动结束时都会调用 restore()，必须有这个函数
    function restore() {
    }

    function fetchBoard() {
        if (page.serverUrl === "") {
            return
        }
        var xhr = new XMLHttpRequest()
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== 4) {
                return
            }
            if (xhr.status === 200) {
                try {
                    var d = JSON.parse(xhr.responseText)
                    page.boardTitle = d.title ? String(d.title) : ""
                    page.boardLines = d.lines ? d.lines : []
                    page.boardStatus = ""
                } catch (e) {
                    page.boardStatus = "bad json"
                }
            } else {
                page.boardStatus = "offline (" + xhr.status + ")"
            }
        }
        xhr.open("GET", page.serverUrl)
        xhr.send()
    }

    Timer {
        interval: page.refreshSeconds * 1000
        repeat: true
        running: page.serverUrl !== ""
        triggeredOnStart: true
        onTriggered: page.fetchBoard()
    }

    Text {
        x: 34
        y: 92
        text: "自定义页"
        color: "white"
        opacity: 0.6
        font.family: page.textFont
        font.pixelSize: 28
    }

    // 实时读数：和官方页面用同一组对象，数值会自动刷新
    Grid {
        x: 30
        y: 140
        columns: 2
        columnSpacing: 30
        rowSpacing: 20

        Repeater {
            model: [
                airdataController.airCO2,
                airdataController.airTVOC,
                airdataController.airPM25,
                airdataController.airTEMP,
                airdataController.airHUMI,
                airdataController.airPMV
            ]
            delegate: Rectangle {
                width: 315
                height: 96
                radius: 14
                color: "#26ffffff"

                Rectangle {
                    x: 14
                    anchors.verticalCenter: parent.verticalCenter
                    width: 6
                    height: parent.height - 28
                    radius: 3
                    color: modelData.evalutionColor
                }
                Text {
                    x: 34
                    y: 10
                    width: 270
                    elide: Text.ElideRight
                    text: modelData.name
                    color: "white"
                    opacity: 0.6
                    font.family: page.textFont
                    font.pixelSize: 20
                }
                Text {
                    id: valueText
                    x: 34
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 6
                    text: modelData.valueString !== "" ? modelData.valueString : "--"
                    color: "white"
                    font.family: page.numFont
                    font.pixelSize: 52
                }
                Text {
                    anchors.left: valueText.right
                    anchors.leftMargin: 8
                    anchors.baseline: valueText.baseline
                    text: modelData.unitString
                    color: "white"
                    opacity: 0.6
                    font.family: page.textFont
                    font.pixelSize: 20
                }
            }
        }
    }

    // 下方：你的自定义内容
    Rectangle {
        x: 30
        y: 496
        width: 660
        height: 194
        radius: 14
        color: "#26ffffff"
        clip: true

        Column {
            x: 20
            y: 14
            width: 620
            spacing: 6

            Text {
                width: 620
                elide: Text.ElideRight
                text: page.boardTitle !== "" ? page.boardTitle : "自定义页已启用"
                color: "white"
                font.family: page.textFont
                font.pixelSize: 26
            }
            Repeater {
                model: page.boardLines
                delegate: Text {
                    width: 620
                    elide: Text.ElideRight
                    text: modelData
                    color: "white"
                    opacity: 0.75
                    font.family: page.textFont
                    font.pixelSize: 22
                }
            }
            Text {
                visible: page.serverUrl === ""
                width: 620
                elide: Text.ElideRight
                text: "编辑 /data/custom/CustomView.qml 修改这里"
                color: "white"
                opacity: 0.5
                font.family: page.textFont
                font.pixelSize: 20
            }
            Text {
                visible: page.boardStatus !== ""
                text: page.boardStatus
                color: "#ffb74d"
                font.family: page.textFont
                font.pixelSize: 20
            }
        }
    }
}
