import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../services/inventory_photo_store.dart';

/// The same private attachment is used in the Inventory and profile detail.
/// The encrypted original is read only on demand; thumbnails decode at 720 px.
class InventoryPhotoAttachment extends StatefulWidget {
  const InventoryPhotoAttachment({
    super.key,
    required this.photoId,
    this.height = 140,
    this.readPhoto,
  });
  final String photoId;
  final double height;
  final Future<Uint8List> Function(String)? readPhoto;

  @override
  State<InventoryPhotoAttachment> createState() =>
      _InventoryPhotoAttachmentState();
}

class _InventoryPhotoAttachmentState extends State<InventoryPhotoAttachment> {
  late Future<Uint8List> _photo;

  @override
  void initState() {
    super.initState();
    _read();
  }

  void _read() {
    _photo =
        (widget.readPhoto ?? InventoryPhotoStore.instance.read)(widget.photoId);
  }

  @override
  void didUpdateWidget(InventoryPhotoAttachment oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.photoId != widget.photoId ||
        oldWidget.readPhoto != widget.readPhoto) {
      _read();
    }
  }

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: SizedBox(
          height: widget.height,
          width: double.infinity,
          child: ColoredBox(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: FutureBuilder<Uint8List>(
              future: _photo,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                      child: TextButton.icon(
                    icon: const Icon(Icons.broken_image_outlined),
                    label: const Text('Foto no disponible · Reintentar'),
                    onPressed: () => setState(_read),
                  ));
                }
                if (!snapshot.hasData) {
                  return const Center(
                      child: SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2)));
                }
                final bytes = snapshot.data!;
                return Semantics(
                  button: true,
                  label: 'Abrir fotografía adjunta',
                  child: InkWell(
                    onTap: () => Navigator.of(context).push<void>(
                        MaterialPageRoute(
                            builder: (_) => _InventoryPhotoView(bytes: bytes))),
                    child: Stack(fit: StackFit.expand, children: [
                      Image.memory(bytes,
                          fit: BoxFit.contain,
                          cacheWidth: 720,
                          excludeFromSemantics: true,
                          errorBuilder: (_, __, ___) => const Center(
                              child: Text('No se pudo mostrar la foto.'))),
                      const Positioned(
                          right: 8,
                          bottom: 8,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                                color: Colors.black54,
                                borderRadius:
                                    BorderRadius.all(Radius.circular(6))),
                            child: Padding(
                                padding: EdgeInsets.all(4),
                                child: Icon(Icons.open_in_full,
                                    color: Colors.white, size: 18)),
                          )),
                    ]),
                  ),
                );
              },
            ),
          ),
        ),
      );
}

class _InventoryPhotoView extends StatelessWidget {
  const _InventoryPhotoView({required this.bytes});
  final Uint8List bytes;

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          title: const Text('Fotografía'),
        ),
        body: SafeArea(
            child: InteractiveViewer(
          minScale: 1,
          maxScale: 5,
          child: SizedBox.expand(
              child: Image.memory(bytes,
                  fit: BoxFit.contain,
                  semanticLabel:
                      'Fotografía adjunta. Puedes ampliarla con dos dedos.')),
        )),
      );
}
