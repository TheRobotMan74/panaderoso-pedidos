import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

import '../ui/theme.dart';
import 'platform.dart';

/// true si se puede mostrar Google Maps. En Android siempre; en la web solo
/// cuando ya está puesta la llave del mapa web y cargó bien.
bool get mapsUsable => !kIsWeb || WebPlatform.mapsReady;

/// Lo que se ve en lugar del mapa cuando la versión web no tiene mapa.
class MapFallback extends StatelessWidget {
  final String message;
  const MapFallback({super.key, required this.message});

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: Pan.crema,
    child: Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.map_rounded, size: 48, color: Pan.canela),
            const SizedBox(height: 10),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Pan.canela),
            ),
          ],
        ),
      ),
    ),
  );
}
