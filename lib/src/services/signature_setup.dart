import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/certificate_profile.dart';
import 'file_service.dart';
import 'pdf_signer_service.dart';
import 'signature_store.dart';

final signatureStoreProvider = FutureProvider<SignatureStore>(
  (ref) async => SignatureStore(await SharedPreferences.getInstance()),
);

final certificateProfilesProvider =
    FutureProvider.autoDispose<List<CertificateProfile>>(
  (ref) async {
    final SignatureStore store =
        await ref.watch(signatureStoreProvider.future);
    return store.loadProfiles();
  },
);

/// Guarda (o actualiza) un certificado y refresca la lista.
Future<void> persistProfile(
    WidgetRef ref, CertificateProfile profile) async {
  final SignatureStore store = await ref.read(signatureStoreProvider.future);
  await store.saveProfile(profile);
  ref.invalidate(certificateProfilesProvider);
}

/// Resultado del flujo "colocar firma": certificado + contraseña del PFX.
class SignSetup {
  const SignSetup({required this.profile, required this.password});

  final CertificateProfile profile;
  final String? password;
}

/// Abre el diálogo para elegir/crear un certificado y su rúbrica opcional.
Future<SignSetup?> showSignSetupDialog(
  BuildContext context,
) {
  return showDialog<SignSetup>(
    context: context,
    builder: (BuildContext context) => const _SignSetupDialog(),
  );
}

class _SignSetupDialog extends ConsumerStatefulWidget {
  const _SignSetupDialog();

  @override
  ConsumerState<_SignSetupDialog> createState() => _SignSetupDialogState();
}

class _SignSetupDialogState extends ConsumerState<_SignSetupDialog> {
  static const String _kNewCertificateId = '__new__';

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _reasonController = TextEditingController();
  final TextEditingController _locationController = TextEditingController();
  final TextEditingController _contactController = TextEditingController();
  String? _selectedCertificateId;
  String? _certificatePath;
  String _certificatePassword = '';
  bool _rememberPassword = false;
  bool _saving = false;
  Uint8ListImage? _rubrica;

  @override
  void initState() {
    super.initState();
    _preselectLastUsed();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _reasonController.dispose();
    _locationController.dispose();
    _contactController.dispose();
    super.dispose();
  }

  List<CertificateProfile> _profiles() =>
      ref.read(certificateProfilesProvider).value ??
      <CertificateProfile>[];

  Future<void> _preselectLastUsed() async {
    final SignatureStore store =
        await ref.read(signatureStoreProvider.future);
    final String? lastId = await store.lastCertificateId;
    if (lastId == null || !mounted) return;
    for (final CertificateProfile p in _profiles()) {
      if (p.id == lastId) {
        _selectCertificate(p);
        break;
      }
    }
  }

  void _selectCertificate(CertificateProfile profile) {
    setState(() {
      _selectedCertificateId = profile.id;
      _certificatePath = profile.certificatePath;
      _nameController.text = profile.name;
      _reasonController.text = profile.reason;
      _locationController.text = profile.location;
      _contactController.text = profile.contact;
      _certificatePassword = '';
      _rubrica = profile.hasRubric
          ? Uint8ListImage(bytes: profile.signatureBytes, name: profile.name)
          : null;
    });
  }

  Future<void> _pickCertificate() async {
    final PickedFile? picked = await FileService().pickCertificate();
    if (picked == null) return;
    final String name = picked.path
        .split(RegExp(r'[\\/]'))
        .last
        .replaceFirst(RegExp(r'\.(pfx|p12)$', caseSensitive: false), '');
    String subject = '';
    final String subjectWithEmpty =
        PdfSignerService().certificateSubject(picked.path, '');
    if (subjectWithEmpty.isNotEmpty) {
      subject = subjectWithEmpty;
    }
    setState(() {
      _selectedCertificateId = _kNewCertificateId;
      _certificatePath = picked.path;
      _certificatePassword = '';
      _nameController.text = subject.isNotEmpty ? subject : name;
      _reasonController.clear();
      _locationController.clear();
      _contactController.clear();
      _rubrica = null;
    });
  }

  Future<void> _createRubric() async {
    final Uint8ListImage? image = await showSignatureDrawDialog(context);
    if (image == null || !mounted) return;
    setState(() => _rubrica = image);
  }

  Future<void> _confirm() async {
    final String? certificatePath = _certificatePath;
    if (certificatePath == null) {
      _showError('Elige un certificado guardado o selecciona un archivo PFX/P12 '
          '(obligatorio).');
      return;
    }

    setState(() => _saving = true);
    try {
      String? password = _certificatePassword;

      CertificateProfile? existing;
      for (final CertificateProfile p in _profiles()) {
        if (p.id == _selectedCertificateId) {
          existing = p;
          break;
        }
      }

      if (password.isEmpty && existing != null) {
        final SignatureStore store =
            await ref.read(signatureStoreProvider.future);
        password = await store.readPassword(existing.id);
      }
      if (password == null || password.isEmpty) {
        _showError('Introduce la contraseña del certificado PFX/P12.');
        return;
      }

      try {
        PdfSignerService().validateCertificate(certificatePath, password);
      } catch (error) {
        _showError(error is ArgumentError ? error.message : '$error');
        return;
      }

      final SignatureStore store =
          await ref.read(signatureStoreProvider.future);
      String name = _nameController.text.trim();
      if (name.isEmpty) {
        name = PdfSignerService()
            .certificateSubject(certificatePath, password);
      }
      final CertificateProfile profile = CertificateProfile(
        id: existing?.id ?? DateTime.now().microsecondsSinceEpoch.toString(),
        name: name.isEmpty
            ? certificatePath
                .split(RegExp(r'[\\/]'))
                .last
            : name,
        reason: _reasonController.text.trim(),
        location: _locationController.text.trim(),
        contact: _contactController.text.trim(),
        certificatePath: certificatePath,
        signatureBytes: _rubrica?.bytes ?? Uint8List(0),
      );
      await persistProfile(ref, profile);

      if (_rememberPassword) {
        await store.savePassword(profile.id, password);
      }
      await store.setLastCertificateId(profile.id);

      if (!mounted) return;
      Navigator.of(context).pop(SignSetup(
        profile: profile,
        password: password,
      ));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final List<CertificateProfile> profiles = _profiles();

    return AlertDialog(
      title: const Text('Configurar firma'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _SectionHeader(
                icon: Icons.key,
                iconColor: Colors.green,
                title: '1. Certificado',
                badge: 'obligatorio',
                badgeColor: Theme.of(context).colorScheme.error,
              ),
              const SizedBox(height: 8),
              if (ref.watch(certificateProfilesProvider).value == null)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(8),
                    child: CircularProgressIndicator(),
                  ),
                )
              else
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    for (final CertificateProfile p in profiles)
                      _CertificateBadge(
                        selected: _selectedCertificateId == p.id,
                        profile: p,
                        onTap: () => _selectCertificate(p),
                      ),
                    ActionChip(
                      avatar: const Icon(Icons.add, size: 18),
                      label: const Text('Nuevo PFX/P12'),
                      onPressed: _saving ? null : _pickCertificate,
                    ),
                  ],
                ),
              if (_certificatePath != null) ...<Widget>[
                const SizedBox(height: 12),
                Text(
                  _certificatePath!.split(RegExp(r'[\\/]')).last,
                  style: Theme.of(context).textTheme.bodySmall,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 12),
                TextField(
                  obscureText: true,
                  onChanged: (String v) => _certificatePassword = v,
                  decoration: const InputDecoration(
                    labelText: 'Contraseña del certificado',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 4),
                CheckboxListTile(
                  value: _rememberPassword,
                  onChanged: (bool? v) =>
                      setState(() => _rememberPassword = v ?? false),
                  title: const Text('Recordar en este equipo',
                      style: TextStyle(fontSize: 13)),
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                ),
              ],
              const SizedBox(height: 12),
              TextField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Nombre / titular',
                  hintText: 'ej. Ana García',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _reasonController,
                decoration: const InputDecoration(
                  labelText: 'Motivo (ej. «Acepto los términos»)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _locationController,
                decoration: const InputDecoration(
                  labelText: 'Lugar (ej. Caracas, Venezuela)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _contactController,
                decoration: const InputDecoration(
                  labelText: 'Contacto (email o teléfono, opcional)',
                  hintText: 'ej. ana@ejemplo.com',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 20),
              _SectionHeader(
                icon: Icons.draw,
                iconColor: Colors.blue,
                title: '2. Rúbrica',
                badge: 'opcional',
                badgeColor: Theme.of(context).colorScheme.outline,
              ),
              const SizedBox(height: 8),
              if (_rubrica != null) ...<Widget>[
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: <Widget>[
                    _CreatedBadge(
                      selected: true,
                      image: _rubrica!,
                      name: _rubrica!.name,
                      onTap: () {},
                    ),
                    ActionChip(
                      avatar: const Icon(Icons.delete_outline, size: 18),
                      label: const Text('Quitar'),
                      onPressed: _saving
                          ? null
                          : () => setState(() => _rubrica = null),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
              ] else ...<Widget>[
                ActionChip(
                  avatar: const Icon(Icons.add, size: 18),
                  label: const Text('Crear / dibujar'),
                  onPressed: _saving ? null : _createRubric,
                ),
                const SizedBox(height: 8),
                Text(
                  'Sin rúbrica: la firma se sellará con una apariencia de '
                  'texto estándar.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _saving ? null : _confirm,
          child: const Text('Usar esta firma'),
        ),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.badge,
    required this.badgeColor,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String badge;
  final Color badgeColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Icon(icon, size: 18, color: iconColor),
        const SizedBox(width: 8),
        Text(title, style: Theme.of(context).textTheme.labelLarge),
        const Spacer(),
        Text(badge,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: badgeColor)),
      ],
    );
  }
}

/// Imagen de rúbrica (PNG) junto con su nombre descriptivo.
class Uint8ListImage {
  const Uint8ListImage({required this.bytes, required this.name});

  final Uint8List bytes;
  final String name;
}

/// Dibuja una nueva rúbrica y devuelve su imagen PNG.
Future<Uint8ListImage?> showSignatureDrawDialog(BuildContext context) async {
  return showDialog<Uint8ListImage>(
    context: context,
    builder: (BuildContext context) => const _SignatureDrawDialog(),
  );
}

const String _kDefaultName = 'Firma';

class _SignatureDrawDialog extends StatefulWidget {
  const _SignatureDrawDialog();

  @override
  State<_SignatureDrawDialog> createState() => _SignatureDrawDialogState();
}

class _SignatureDrawDialogState extends State<_SignatureDrawDialog> {
  final TextEditingController _nameController = TextEditingController();
  final List<List<Offset>> _strokes = <List<Offset>>[];
  List<Offset>? _currentStroke;
  Uint8List? _importedImage;
  bool _busy = false;
  Size _canvasSize = Size.zero;

  static const double _kExportWidth = 900;
  static const double _kExportHeight = 300;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _importImage() async {
    final PickedFile? picked = await FileService().pickSignatureImage();
    if (picked == null) return;
    setState(() => _importedImage = picked.bytes);
  }

  void _undo() {
    setState(() {
      if (_strokes.isNotEmpty) _strokes.removeLast();
    });
  }

  void _clear() => setState(_strokes.clear);

  Future<void> _accept() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      Uint8List bytes;
      if (_importedImage != null) {
        bytes = _importedImage!;
      } else if (_strokes.isNotEmpty) {
        bytes = await _renderStrokesPng();
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(const SnackBar(
              content: Text('Dibuja tu firma o importa una imagen.')));
        return;
      }
      if (!mounted) return;
      Navigator.of(context).pop(Uint8ListImage(
        bytes: bytes,
        name: _nameController.text.trim().isEmpty
            ? _kDefaultName
            : _nameController.text.trim(),
      ));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<Uint8List> _renderStrokesPng() async {
    const Size target = Size(_kExportWidth, _kExportHeight);
    final ui.PictureRecorder recorder = ui.PictureRecorder();
    final ui.Canvas canvas = ui.Canvas(recorder);
    canvas.drawRect(
        Offset.zero & target, ui.Paint()..color = const Color(0x00000000));

    final double scaleX = _canvasSize.width == 0
        ? 1
        : target.width / _canvasSize.width;
    final double scaleY = _canvasSize.height == 0
        ? 1
        : target.height / _canvasSize.height;
    canvas.scale(scaleX, scaleY);

    final ui.Paint paint = ui.Paint()
      ..color = const Color(0xFF1B1B1F)
      ..style = ui.PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = ui.StrokeCap.round
      ..strokeJoin = ui.StrokeJoin.round;

    for (final List<Offset> stroke in _strokes) {
      if (stroke.length < 2) continue;
      final ui.Path path = ui.Path()..moveTo(stroke.first.dx, stroke.first.dy);
      for (final Offset point in stroke.skip(1)) {
        path.lineTo(point.dx, point.dy);
      }
      canvas.drawPath(path, paint);
    }

    final ui.Image image = await recorder.endRecording().toImage(
          target.width.round(),
          target.height.round(),
        );
    final ByteData? png = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return Uint8List.fromList(png?.buffer.asUint8List() ?? <int>[]);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Dibuja tu firma'),
      content: SizedBox(
        width: 720,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            AspectRatio(
              aspectRatio: 3,
              child: LayoutBuilder(
                builder: (BuildContext context, BoxConstraints constraints) {
                  _canvasSize = constraints.biggest;
                  return Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border.all(
                        color: Theme.of(context).dividerColor,
                        width: 1,
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: GestureDetector(
                      onPanDown: (DragDownDetails details) => setState(() {
                        _currentStroke = <Offset>[details.localPosition];
                        _strokes.add(_currentStroke!);
                      }),
                      onPanUpdate: (DragUpdateDetails details) =>
                          setState(() {
                        _currentStroke?.add(details.localPosition);
                      }),
                      child: CustomPaint(
                        painter: _StrokePainter(_strokes),
                        child: const SizedBox.expand(),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Nombre para este perfil',
                hintText: 'ej. Firma de Ana',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(onPressed: _undo, child: const Text('Deshacer')),
        TextButton(onPressed: _clear, child: const Text('Borrar')),
        TextButton(onPressed: _importImage, child: const Text('Importar imagen')),
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _busy ? null : _accept,
          child: const Text('Aceptar'),
        ),
      ],
    );
  }
}

class _StrokePainter extends CustomPainter {
  _StrokePainter(this.strokes);

  final List<List<Offset>> strokes;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = const Color(0xFF1B1B1F)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    for (final List<Offset> stroke in strokes) {
      if (stroke.isEmpty) continue;
      final Path path = Path()..moveTo(stroke.first.dx, stroke.first.dy);
      for (final Offset point in stroke.skip(1)) {
        path.lineTo(point.dx, point.dy);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(_StrokePainter oldDelegate) => true;
}

class _CertificateBadge extends StatelessWidget {
  const _CertificateBadge({
    required this.selected,
    required this.profile,
    required this.onTap,
  });

  final bool selected;
  final CertificateProfile profile;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return ChoiceChip(
      selected: selected,
      selectedColor: scheme.primaryContainer,
      avatar: const Icon(Icons.key, size: 16),
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(profile.name),
          if (profile.hasRubric) ...<Widget>[
            const SizedBox(width: 6),
            Icon(Icons.gesture, size: 14, color: scheme.onSurfaceVariant),
          ],
        ],
      ),
      tooltip: profile.hasRubric
          ? '${profile.name} — con rúbrica'
          : '${profile.name} — sin rúbrica',
      onSelected: (_) => onTap(),
    );
  }
}

class _CreatedBadge extends StatelessWidget {
  const _CreatedBadge({
    required this.selected,
    required this.image,
    required this.name,
    required this.onTap,
  });

  final bool selected;
  final Uint8ListImage image;
  final String name;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return ChoiceChip(
      selected: selected,
      selectedColor: scheme.primaryContainer,
      avatar: CircleAvatar(
        backgroundColor: Colors.white,
        backgroundImage: MemoryImage(image.bytes),
      ),
      label: Text(name),
      onSelected: (_) => onTap(),
    );
  }
}