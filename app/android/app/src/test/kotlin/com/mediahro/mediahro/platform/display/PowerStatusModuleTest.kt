package com.mediahro.mediahro.platform.display

import android.os.PowerManager
import com.mediahro.mediahro.pigeon.ThermalLevelMsg
import org.junit.Assert.assertEquals
import org.junit.Test

class PowerStatusModuleTest {
    @Test
    fun `ADR-033 every Android thermal step maps to a shared level`() {
        assertEquals(ThermalLevelMsg.NOMINAL, PowerStatusModule.levelOf(PowerManager.THERMAL_STATUS_NONE))
        assertEquals(ThermalLevelMsg.FAIR, PowerStatusModule.levelOf(PowerManager.THERMAL_STATUS_LIGHT))
        assertEquals(ThermalLevelMsg.SERIOUS, PowerStatusModule.levelOf(PowerManager.THERMAL_STATUS_MODERATE))
        for (s in listOf(
            PowerManager.THERMAL_STATUS_SEVERE,
            PowerManager.THERMAL_STATUS_CRITICAL,
            PowerManager.THERMAL_STATUS_EMERGENCY,
            PowerManager.THERMAL_STATUS_SHUTDOWN,
        )) {
            assertEquals(ThermalLevelMsg.CRITICAL, PowerStatusModule.levelOf(s))
        }
    }
}
