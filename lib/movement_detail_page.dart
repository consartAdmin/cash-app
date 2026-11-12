import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import 'api_service.dart';
import 'lookups.dart';
import 'models.dart';
import 'movement_form_page.dart';
import 'ui.dart';

/// Detalhe da movimentação, com anexos.
class MovementDetailPage extends StatefulWidget {
  final Movement movement;
  const MovementDetailPage({super.key, required this.movement});

  @override
  State<MovementDetailPage> createState() => _MovementDetailPageState();
}

class _MovementDetailPageState extends State<MovementDetailPage> {
  final _api = ApiService.instance;
  late Movement _m = widget.movement;
  List<Attachment> _files = const [];
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final r = await Future.wait([
        _api.movement(_m.id),
        _api.attachments(_m.id),
      ]);
      if (!mounted) return;
      setState(() {
        _m = r[0] as Movement;
        _files = r[1] as List<Attachment>;
      });
    } catch (e) {
      if (mounted) showSnack(context, e.toString(), error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _addPhoto() async {
    final source = await pickPhotoSource(context);
    if (source == null) return;
    final x = await ImagePicker()
        .pickImage(source: source, maxWidth: 2000, imageQuality: 75);
    if (x == null) return;
    setState(() => _busy = true);
    try {
      await _api.uploadAttachment(_m.id, await x.readAsBytes(), x.name);
      notifyDataChanged();
      await _load();
      if (mounted) showSnack(context, 'Anexo enviado.');
    } catch (e) {
      if (mounted) showSnack(context, e.toString(), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openFile(Attachment a) async {
    final url = await _api.attachmentUrl(a);
    if (url.isEmpty) return;
    final ok =
        await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    if (!ok && mounted) showSnack(context, 'Não foi possível abrir o anexo.');
  }

  Future<void> _deleteFile(Attachment a) async {
    final ok = await confirm(context, 'Excluir anexo',
        'Excluir "${a.name}"? Não dá para desfazer.');
    if (!ok) return;
    try {
      await _api.deleteAttachment(_m.id, a.id);
      notifyDataChanged();
      await _load();
    } catch (e) {
      if (mounted) showSnack(context, e.toString(), error: true);
    }
  }

  Future<void> _delete() async {
    final what = _m.isTransfer
        ? 'Excluir a transferência? As duas pontas (saída e entrada) serão apagadas.'
        : 'Excluir este lançamento de ${money(_m.total)}? Não dá para desfazer.';
    if (!await confirm(context, 'Excluir', what)) return;
    setState(() => _busy = true);
    try {
      await _api.deleteMovement(_m);
      notifyDataChanged();
      if (!mounted) return;
      Navigator.pop(context);
      showSnack(context, 'Lançamento excluído.');
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        showSnack(context, e.toString(), error: true);
      }
    }
  }

  Future<void> _edit() async {
    if (_m.isTransfer) {
      showSnack(context,
          'Transferências são editadas no ERP. Aqui você pode excluir e lançar de novo.');
      return;
    }
    final saved = await Navigator.of(context).push<bool>(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => MovementFormPage(editing: _m),
    ));
    if (saved == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = moveColor(_m);
    final typeLabel = _m.isTransfer
        ? 'TRANSFERÊNCIA'
        : (_m.type == MoveType.entrada ? 'ENTRADA' : 'SAÍDA');
    final extras = [
      if (_m.penalty > 0) 'multa ${money(_m.penalty)}',
      if (_m.interest > 0) 'juros ${money(_m.interest)}',
      if (_m.fee > 0) 'encargos ${money(_m.fee)}',
    ];
    return Scaffold(
      appBar: AppBar(
        title: const Text('Movimentação'),
        actions: [
          if (!_m.isTransfer)
            IconButton(
                tooltip: 'Editar',
                onPressed: _busy ? null : _edit,
                icon: const Icon(Icons.edit_outlined)),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            if (_loading || _busy) const LinearProgressIndicator(minHeight: 2),
            Card(
              color: Color.alphaBlend(
                  c.withValues(alpha: 0.12), theme.colorScheme.surface),
              elevation: 0,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surface,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(typeLabel,
                          style: TextStyle(fontSize: 11, color: c)),
                    ),
                    const SizedBox(height: 8),
                    Text(_m.title,
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(money(_m.total),
                        style: theme.textTheme.headlineMedium
                            ?.copyWith(color: c, fontWeight: FontWeight.w600)),
                    if (extras.isNotEmpty)
                      Text('Valor ${money(_m.amount)} + ${extras.join(' + ')}',
                          style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
            ),
            Card(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Column(children: [
                  InfoRow('Data', formatDateTime(_m.date)),
                  InfoRow('Conta', _m.account),
                  if (_m.isTransfer)
                    InfoRow('Transferência',
                        '${_m.transferFrom} → ${_m.transferTo}')
                  else
                    InfoRow('Categoria', _m.categoryLabel),
                  InfoRow(
                      'Documento',
                      '${_m.documentType} ${_m.documentNumber}'.trim()),
                  InfoRow('Fornecedor', _m.supplier),
                  InfoRow('Nota fiscal', _m.fiscalDoc),
                  InfoRow('Observação', _m.notes),
                ]),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 12, 4, 6),
              child: Text('Anexos (${_files.length})',
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w600)),
            ),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final a in _files)
                _FileTile(
                  a,
                  onTap: () => _openFile(a),
                  onLongPress: () => _deleteFile(a),
                ),
              _AddTile(onTap: _busy ? null : _addPhoto),
            ]),
            if (_files.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6, left: 4),
                child: Text('Toque para abrir · segure para excluir',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.outline)),
              ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          child: Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _busy ? null : _delete,
                style: OutlinedButton.styleFrom(
                    foregroundColor: outColor,
                    minimumSize: const Size.fromHeight(48)),
                icon: const Icon(Icons.delete_outline),
                label: const Text('Excluir'),
              ),
            ),
            if (!_m.isTransfer) ...[
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _busy ? null : _edit,
                  style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(48)),
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Editar'),
                ),
              ),
            ],
          ]),
        ),
      ),
    );
  }
}

class _FileTile extends StatelessWidget {
  final Attachment a;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  const _FileTile(this.a, {required this.onTap, required this.onLongPress});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pdf = a.name.toLowerCase().endsWith('.pdf');
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: 84,
        height: 84,
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: theme.colorScheme.secondaryContainer,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(pdf ? Icons.picture_as_pdf_outlined : Icons.image_outlined,
                color: theme.colorScheme.onSecondaryContainer),
            const SizedBox(height: 4),
            Text(a.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: theme.textTheme.labelSmall),
          ],
        ),
      ),
    );
  }
}

class _AddTile extends StatelessWidget {
  final VoidCallback? onTap;
  const _AddTile({this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme.primary;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: 84,
        height: 84,
        decoration: BoxDecoration(
          border: Border.all(color: c, width: 1.5),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add_a_photo_outlined, color: c),
            const SizedBox(height: 4),
            Text('Adicionar\nfoto',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11, color: c)),
          ],
        ),
      ),
    );
  }
}

Future<ImageSource?> pickPhotoSource(BuildContext context) {
  return showModalBottomSheet<ImageSource>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(
          leading: const Icon(Icons.photo_camera_outlined),
          title: const Text('Tirar foto'),
          onTap: () => Navigator.pop(ctx, ImageSource.camera),
        ),
        ListTile(
          leading: const Icon(Icons.photo_library_outlined),
          title: const Text('Escolher da galeria'),
          onTap: () => Navigator.pop(ctx, ImageSource.gallery),
        ),
      ]),
    ),
  );
}

Future<bool> confirm(BuildContext context, String title, String text) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(text),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar')),
        FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Confirmar')),
      ],
    ),
  );
  return r == true;
}
