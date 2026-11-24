package mx.panaderoso.panaderoso_pedidos

import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        crearCanalDeAvisos()
    }

    // Canal "avisos" con prioridad alta: así los avisos salen como ventanita arriba
    // de la pantalla (no solo en la barra). AndroidManifest.xml lo pone como canal
    // por defecto de Firebase. Android solo lo crea la primera vez; después ya existe.
    private fun crearCanalDeAvisos() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val canal = NotificationChannel(
            "avisos",
            "Avisos de tu pedido",
            NotificationManager.IMPORTANCE_HIGH,
        ).apply {
            description = "Cuando confirmamos tu pedido, va en camino o ya está cerca."
            enableVibration(true)
        }
        getSystemService(NotificationManager::class.java)?.createNotificationChannel(canal)
    }
}
