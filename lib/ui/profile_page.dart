import 'package:firebase_auth/firebase_auth.dart';
import 'package:material_ui/material_ui.dart';

import '../models.dart';
import '../services/repo.dart';

/// Datos del cliente: nombre, teléfono y dirección de entrega.
class ProfilePage extends StatefulWidget {
  final String uid;
  final AppUser? existing;

  /// true cuando se abre desde el menú para editar (muestra botón de regresar).
  final bool editing;

  const ProfilePage({super.key, required this.uid, this.existing, this.editing = false});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  late final _name = TextEditingController(text: widget.existing?.name);
  late final _phone = TextEditingController(text: widget.existing?.phone);
  late final _address = TextEditingController(text: widget.existing?.address);
  late final _notes = TextEditingController(text: widget.existing?.addressNotes);
  final _form = GlobalKey<FormState>();
  bool _busy = false;

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    await Repo.instance.saveProfile(AppUser(
      uid: widget.uid,
      name: _name.text.trim(),
      phone: _phone.text.trim(),
      address: _address.text.trim(),
      addressNotes: _notes.text.trim(),
    ));
    if (!mounted) return;
    setState(() => _busy = false);
    if (widget.editing) Navigator.pop(context);
  }

  String? _required(String? v) => (v == null || v.trim().isEmpty) ? 'Falta este dato' : null;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tus datos de entrega'),
        actions: [
          if (!widget.editing)
            TextButton(
              onPressed: () => FirebaseAuth.instance.signOut(),
              child: const Text('Salir'),
            ),
        ],
      ),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            TextFormField(
              controller: _name,
              validator: _required,
              decoration: const InputDecoration(labelText: 'Nombre', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _phone,
              validator: _required,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                  labelText: 'Teléfono (WhatsApp)', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _address,
              validator: _required,
              maxLines: 2,
              decoration: const InputDecoration(
                  labelText: 'Dirección: calle, número y colonia', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _notes,
              decoration: const InputDecoration(
                labelText: 'Referencias (opcional)',
                hintText: 'Ej. portón negro, tocar el timbre',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 20),
            FilledButton(onPressed: _busy ? null : _save, child: const Text('Guardar')),
          ],
        ),
      ),
    );
  }
}
