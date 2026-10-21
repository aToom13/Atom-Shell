import QtQuick
import Quickshell.Services.UPower
import qs.components
import qs.services
import qs.utils

MaterialIcon {
    required property color colour

    animate: true
    text: {
        if (!UPower.displayDevice.isLaptopBattery) {
            if (PowerProfiles.profile === PowerProfile.PowerSaver)
                return "energy_savings_leaf";
            if (PowerProfiles.profile === PowerProfile.Performance)
                return "rocket_launch";
            return "balance";
        }
        return Icons.getBatteryIcon(BatteryEstimator.displayPercentage, [UPowerDeviceState.Charging, UPowerDeviceState.FullyCharged, UPowerDeviceState.PendingCharge].includes(UPower.displayDevice.state));
    }
    color: !UPower.onBattery || BatteryEstimator.displayPercentage > 0.2 ? colour : Colours.palette.m3error
    fill: 1
}
