import QtQuick
import Caelestia.Config
import qs.services

ColorAnimation {
    duration: GameMode.reduceAnimations ? 0 : Tokens.anim.durations.expressiveSlowEffects
    easing: Tokens.anim.expressiveSlowEffects
}
