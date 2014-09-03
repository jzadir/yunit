/*
 * Copyright 2014 Canonical Ltd.
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation; version 3.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with this program. If not, see <http://www.gnu.org/licenses/>.
 */

import QtQuick 2.0
import Ubuntu.Components 1.1
import Unity.Application 0.1

Item {
    id: root

    // to be read from outside
    readonly property bool fullscreen: application ? application.fullscreen : false
    property alias interactive: sessionContainer.interactive

    // to be set from outside
    property QtObject application

    QtObject {
        id: d

        // helpers so that we don't have to check for the existence of an application everywhere
        // (in order to avoid breaking qml binding due to a javascript exception)
        readonly property string name: root.application ? root.application.name : ""
        readonly property url icon: root.application ? root.application.icon : ""
        readonly property int applicationState: root.application ? root.application.state : -1

        // Whether the Application had a surface before but lost it.
        property bool hadSurface: sessionContainer.surfaceContainer.hadSurface

        property bool needToTakeScreenshot:
            sessionContainer.surface && d.surfaceInitialized && screenshotImage.status === Image.Null
            && d.applicationState === ApplicationInfoInterface.Stopped
        onNeedToTakeScreenshotChanged: {
            if (needToTakeScreenshot) {
                screenshotImage.take();
            }
        }

        //FIXME - this is a hack to avoid the first few rendered frames as they
        // might show the UI accommodating due to surface resizes on startup.
        // Remove this when possible
        property bool surfaceInitialized: false

        function forceSurfaceActiveFocusIfReady() {
            if (sessionContainer.surface.focus &&
                    sessionContainer.surface.parent === sessionContainer.surfaceContainer &&
                    sessionContainer.surface.enabled) {
                sessionContainer.surface.forceActiveFocus();
            }
        }
    }

    Timer {
        id: surfaceInitTimer
        interval: 100
        onTriggered: { if (sessionContainer.surface) {d.surfaceInitialized = true;} }
    }

    Connections {
        target: sessionContainer.surface
        // FIXME: I would rather not need to do this, but currently it doesn't get
        // active focus without it and I don't know why.
        onFocusChanged: d.forceSurfaceActiveFocusIfReady();
        onParentChanged: d.forceSurfaceActiveFocusIfReady();
        onEnabledChanged: d.forceSurfaceActiveFocusIfReady();
    }

    Image {
        id: screenshotImage
        objectName: "screenshotImage"
        source: ""
        anchors.fill: parent

        function take() {
            // Format: "image://application/$APP_ID/$CURRENT_TIME_MS"
            // eg: "image://application/calculator-app/123456"
            var timeMs = new Date().getTime();
            source = "image://application/" + root.application.appId + "/" + timeMs;
        }

        // Save memory by using a half-resolution (thus quarter size) screenshot
        sourceSize.width: root.width / 2
        sourceSize.height: root.height / 2
    }

    Loader {
        id: splashLoader
        visible: active
        active: false
        anchors.fill: parent
        sourceComponent: Component {
            Splash { name: d.name; image: d.icon }
        }
    }

    SessionContainer {
        id: sessionContainer
        session: application ? application.session : null
        anchors.fill: parent

        onSurfaceChanged: {
            if (sessionContainer.surface) {
                surfaceInitTimer.start();
            } else {
                d.surfaceInitialized = false;
            }
            d.forceSurfaceActiveFocusIfReady();
        }
    }

    StateGroup {
        objectName: "applicationWindowStateGroup"
        states: [
            State {
                name: "void"
                when:
                     d.hadSurface && (!sessionContainer.surface || !d.surfaceInitialized)
                     &&
                     screenshotImage.status !== Image.Ready
            },
            State {
                name: "splashScreen"
                when:
                     !d.hadSurface && (!sessionContainer.surface || !d.surfaceInitialized)
                     &&
                     screenshotImage.status !== Image.Ready
            },
            State {
                name: "surface"
                when:
                      (sessionContainer.surface && d.surfaceInitialized)
                      &&
                      (d.applicationState !== ApplicationInfoInterface.Stopped
                       || screenshotImage.status !== Image.Ready)
            },
            State {
                name: "screenshot"
                when:
                      screenshotImage.status === Image.Ready
                      &&
                      (d.applicationState === ApplicationInfoInterface.Stopped
                       || !sessionContainer.surface || !d.surfaceInitialized)
            }
        ]

        transitions: [
            Transition {
                from: ""; to: "splashScreen"
                PropertyAction { target: splashLoader; property: "active"; value: true }
                PropertyAction { target: sessionContainer.surfaceContainer
                                 property: "visible"; value: false }
            },
            Transition {
                from: "splashScreen"; to: "surface"
                SequentialAnimation {
                    PropertyAction { target: sessionContainer.surfaceContainer
                                     property: "opacity"; value: 0.0 }
                    PropertyAction { target: sessionContainer.surfaceContainer
                                     property: "visible"; value: true }
                    UbuntuNumberAnimation { target: sessionContainer.surfaceContainer; property: "opacity";
                                            from: 0.0; to: 1.0
                                            duration: UbuntuAnimation.BriskDuration }
                    PropertyAction { target: splashLoader; property: "active"; value: false }
                }
            },
            Transition {
                from: "surface"; to: "splashScreen"
                SequentialAnimation {
                    PropertyAction { target: splashLoader; property: "active"; value: true }
                    PropertyAction { target: sessionContainer.surfaceContainer
                                     property: "visible"; value: true }
                    UbuntuNumberAnimation { target: splashLoader; property: "opacity";
                                            from: 0.0; to: 1.0
                                            duration: UbuntuAnimation.BriskDuration }
                    PropertyAction { target: sessionContainer.surfaceContainer
                                     property: "visible"; value: false }
                }
            },
            Transition {
                from: "surface"; to: "screenshot"
                SequentialAnimation {
                    PropertyAction { target: screenshotImage
                                     property: "visible"; value: true }
                    UbuntuNumberAnimation { target: screenshotImage; property: "opacity";
                                            from: 0.0; to: 1.0
                                            duration: UbuntuAnimation.BriskDuration }
                    PropertyAction { target: sessionContainer.surfaceContainer
                                     property: "visible"; value: false }
                    ScriptAction { script: { if (sessionContainer.session) { sessionContainer.session.release(); } } }
                }
            },
            Transition {
                from: "screenshot"; to: "surface"
                SequentialAnimation {
                    PropertyAction { target: sessionContainer.surfaceContainer
                                     property: "visible"; value: true }
                    UbuntuNumberAnimation { target: screenshotImage; property: "opacity";
                                            from: 1.0; to: 0.0
                                            duration: UbuntuAnimation.BriskDuration }
                    PropertyAction { target: screenshotImage; property: "visible"; value: false }
                    PropertyAction { target: screenshotImage; property: "source"; value: "" }
                }
            },
            Transition {
                from: "surface"; to: "void"
                SequentialAnimation {
                    PropertyAction { target: sessionContainer.surfaceContainer; property: "visible"; value: false }
                    ScriptAction { script: { if (sessionContainer.session) { sessionContainer.session.release(); } } }
                }
            },
            Transition {
                from: "void"; to: "surface"
                SequentialAnimation {
                    PropertyAction { target: sessionContainer.surfaceContainer; property: "opacity"; value: 0.0 }
                    PropertyAction { target: sessionContainer.surfaceContainer; property: "visible"; value: true }
                    UbuntuNumberAnimation { target: sessionContainer.surfaceContainer; property: "opacity";
                                            from: 0.0; to: 1.0
                                            duration: UbuntuAnimation.BriskDuration }
                }
            }
        ]
    }

}