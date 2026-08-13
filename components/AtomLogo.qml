import QtQuick
import Caelestia.Config
import qs.services

Item {
    id: root

    property color colour: Colours.palette.m3onSurface

    implicitWidth: 150
    implicitHeight: 100

    onColourChanged: canvas.requestPaint()

    Canvas {
        id: canvas

        anchors.centerIn: parent
        width: 126
        height: 92
        renderTarget: Canvas.FramebufferObject

        onPaint: {
            const ctx = getContext("2d");
            ctx.reset();
            ctx.translate(width / 2, height / 2);
            ctx.strokeStyle = root.colour;
            ctx.fillStyle = root.colour;
            ctx.lineWidth = 4.5;
            ctx.lineCap = "round";

            for (const angle of [0, Math.PI / 3, -Math.PI / 3]) {
                ctx.save();
                ctx.rotate(angle);
                ctx.beginPath();
                ctx.ellipse(-52, -18, 104, 36);
                ctx.stroke();
                ctx.restore();
            }

            ctx.beginPath();
            ctx.arc(0, 0, 8, 0, Math.PI * 2);
            ctx.fill();
        }
    }
}
