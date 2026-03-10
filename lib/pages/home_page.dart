import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:gal/gal.dart';
import 'package:google_mlkit_subject_segmentation/google_mlkit_subject_segmentation.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

import '../widgets/checkerboard.dart';

const _bg = Color(0xFF0F0F0F);
const _surface = Color(0xFF1A1A1A);
const _border = Color(0xFF2A2A2A);

enum _Stage { idle, selected, processing, done }

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with TickerProviderStateMixin {
  File? _file;
  Uint8List? _result;
  _Stage _stage = _Stage.idle;
  bool _showOriginal = false;

  final _zoomCtrl = TransformationController();

  final _segmenter = SubjectSegmenter(
    options: SubjectSegmenterOptions(
      enableForegroundBitmap: false,
      enableForegroundConfidenceMask: true,
      enableMultipleSubjects: SubjectResultOptions(
        enableConfidenceMask: false,
        enableSubjectBitmap: false,
      ),
    ),
  );

  late final AnimationController _scanCtrl;
  late final Animation<double> _scanAnim;
  late final AnimationController _revealCtrl;
  late final Animation<double> _revealFade;

  @override
  void initState() {
    super.initState();
    _scanCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));
    _scanAnim = Tween<double>(begin: 0, end: 1)
        .animate(CurvedAnimation(parent: _scanCtrl, curve: Curves.linear));
    _revealCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 500));
    _revealFade = CurvedAnimation(parent: _revealCtrl, curve: Curves.easeOut);
  }

  @override
  void dispose() {
    _scanCtrl.dispose();
    _revealCtrl.dispose();
    _zoomCtrl.dispose();
    _segmenter.close();
    super.dispose();
  }

  // ─── Actions ────────────────────────────────────────────────────────────────

  Future<void> _pick(ImageSource src) async {
    final x = await ImagePicker().pickImage(source: src, imageQuality: 92);
    if (x == null) return;
    _revealCtrl.reset();
    _zoomCtrl.value = Matrix4.identity();
    setState(() {
      _file = File(x.path);
      _result = null;
      _stage = _Stage.selected;
      _showOriginal = false;
    });
  }

  Future<void> _process() async {
    if (_file == null) return;
    setState(() => _stage = _Stage.processing);
    _scanCtrl.repeat();

    try {
      final inputImage = InputImage.fromFilePath(_file!.path);
      final seg = await _segmenter.processImage(inputImage);
      final rawMask = seg.foregroundConfidenceMask;
      if (rawMask == null) throw Exception('No mask');

      final mask = Float32List.fromList(
        rawMask.map((e) => (e as num).toDouble()).toList(),
      );
      final bytes = await _file!.readAsBytes();
      final out = await compute(_isolateApplyMask, {'bytes': bytes, 'mask': mask});

      _scanCtrl.stop();
      _scanCtrl.reset();
      setState(() {
        _result = out;
        _stage = _Stage.done;
      });
      _revealCtrl.forward();
    } catch (e) {
      _scanCtrl.stop();
      _scanCtrl.reset();
      setState(() => _stage = _Stage.selected);
      _snack('Lỗi: $e');
    }
  }

  Future<void> _save() async {
    if (_result == null) return;
    try {
      await Gal.putImageBytes(_result!);
      _snack('Đã lưu vào thư viện');
    } catch (e) {
      _snack('Lỗi lưu: $e');
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      behavior: SnackBarBehavior.floating,
      backgroundColor: _surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: _border),
      ),
      margin: const EdgeInsets.all(16),
    ));
  }

  // ─── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: Column(
          children: [
            _header(),
            Expanded(child: _canvas()),
            _bottomBar(),
          ],
        ),
      ),
    );
  }

  Widget _header() {
    final done = _stage == _Stage.done;
    final busy = _stage == _Stage.processing;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
      child: Row(
        children: [
          _ToolBtn(
            icon: Icons.photo_library_outlined,
            tooltip: 'Thư viện',
            enabled: !busy,
            onTap: () => _pick(ImageSource.gallery),
          ),
          const SizedBox(width: 6),
          _ToolBtn(
            icon: Icons.camera_alt_outlined,
            tooltip: 'Camera',
            enabled: !busy,
            onTap: () => _pick(ImageSource.camera),
          ),
          const Spacer(),
          _ToolBtn(
            icon: Icons.compare_rounded,
            tooltip: 'So sánh',
            enabled: done,
            active: _showOriginal,
            onTap: () => setState(() => _showOriginal = !_showOriginal),
          ),
          const SizedBox(width: 6),
          _ToolBtn(
            icon: Icons.save_alt_rounded,
            tooltip: 'Lưu',
            enabled: done,
            onTap: _save,
          ),
        ],
      ),
    );
  }

  Widget _canvas() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          transitionBuilder: (child, anim) => FadeTransition(opacity: anim, child: child),
          child: switch (_stage) {
            _Stage.idle => _emptyState(),
            _Stage.selected => InteractiveViewer(
                key: ValueKey(_file?.path),
                transformationController: _zoomCtrl,
                minScale: 1.0,
                maxScale: 6.0,
                clipBehavior: Clip.none,
                child: SizedBox.expand(
                  child: Image.file(_file!, fit: BoxFit.contain),
                ),
              ),
            _Stage.processing => _processingState(),
            _Stage.done => InteractiveViewer(
                key: const ValueKey('done'),
                transformationController: _zoomCtrl,
                minScale: 1.0,
                maxScale: 6.0,
                clipBehavior: Clip.none,
                child: _doneState(),
              ),
          },
        ),
      ),
    );
  }

  Widget _emptyState() {
    return GestureDetector(
      key: const ValueKey('idle'),
      onTap: _showPicker,
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: _surface,
          border: Border.all(color: _border),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.add_photo_alternate_outlined, color: Colors.white38, size: 48),
            const SizedBox(height: 16),
            const Text('Chọn ảnh',
                style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Text('Thư viện hoặc camera',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.35), fontSize: 13)),
          ],
        ),
      ),
    );
  }

  Widget _processingState() {
    return Stack(
      key: const ValueKey('processing'),
      fit: StackFit.expand,
      children: [
        Image.file(_file!, fit: BoxFit.contain),
        Container(color: Colors.black.withValues(alpha: 0.6)),
        AnimatedBuilder(
          animation: _scanAnim,
          builder: (context, child) => CustomPaint(painter: _ShimmerPainter(phase: _scanAnim.value)),
        ),
        const Align(
          alignment: Alignment(0, 0.82),
          child: _StatusPill(label: 'Đang xử lý...'),
        ),
      ],
    );
  }

  Widget _doneState() {
    return FadeTransition(
      opacity: _revealFade,
      child: Stack(
        fit: StackFit.expand,
        children: [
          _showOriginal
              ? Image.file(_file!, fit: BoxFit.contain)
              : CheckerboardBackground(
                  child: Image.memory(_result!, fit: BoxFit.contain)),
          Positioned(
            top: 10,
            left: 12,
            child: _Label(_showOriginal ? 'Gốc' : 'Đã xóa nền'),
          ),
        ],
      ),
    );
  }

  Widget _bottomBar() {
    final busy = _stage == _Stage.processing;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 20),
      child: _PrimaryBtn(
        label: _stage == _Stage.done ? 'Làm lại' : 'Xóa nền',
        isLoading: busy,
        enabled: _file != null && !busy,
        onTap: _process,
      ),
    );
  }

  void _showPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: _surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        side: BorderSide(color: _border),
      ),
      builder: (_) => _PickerSheet(onPick: _pick),
    );
  }
}

// ─── Widgets ──────────────────────────────────────────────────────────────────

class _ToolBtn extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final bool active;
  final bool enabled;
  final VoidCallback onTap;

  const _ToolBtn({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.active = false,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        child: AnimatedOpacity(
          opacity: enabled ? 1.0 : 0.25,
          duration: const Duration(milliseconds: 200),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: active ? Colors.white : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: active ? Colors.white : Colors.white24),
            ),
            child: Icon(icon, size: 20, color: active ? _bg : Colors.white),
          ),
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  final String label;
  const _StatusPill({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white24),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 14, height: 14,
            child: CircularProgressIndicator(
              strokeWidth: 1.5,
              valueColor: AlwaysStoppedAnimation(Colors.white70),
            ),
          ),
          const SizedBox(width: 8),
          Text(label,
              style: const TextStyle(
                  color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(text,
          style: const TextStyle(
              color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
    );
  }
}

class _PrimaryBtn extends StatefulWidget {
  final String label;
  final bool isLoading;
  final bool enabled;
  final VoidCallback onTap;
  const _PrimaryBtn(
      {required this.label,
      required this.isLoading,
      required this.enabled,
      required this.onTap});

  @override
  State<_PrimaryBtn> createState() => _PrimaryBtnState();
}

class _PrimaryBtnState extends State<_PrimaryBtn> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.enabled ? widget.onTap : null,
      onTapDown: (_) => setState(() => _down = true),
      onTapUp: (_) => setState(() => _down = false),
      onTapCancel: () => setState(() => _down = false),
      child: AnimatedOpacity(
        opacity: widget.enabled ? 1 : 0.4,
        duration: const Duration(milliseconds: 150),
        child: AnimatedScale(
          scale: _down ? 0.97 : 1,
          duration: const Duration(milliseconds: 80),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 15),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: widget.isLoading
                  ? const SizedBox(
                      width: 18, height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation(_bg),
                      ),
                    )
                  : Text(widget.label,
                      style: const TextStyle(
                          color: _bg, fontSize: 15, fontWeight: FontWeight.w700)),
            ),
          ),
        ),
      ),
    );
  }
}

class _PickerSheet extends StatelessWidget {
  final Future<void> Function(ImageSource) onPick;
  const _PickerSheet({required this.onPick});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 32, height: 3,
                decoration: BoxDecoration(
                    color: Colors.white24, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 20),
            const Text('Chọn ảnh từ',
                style: TextStyle(
                    color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.photo_library_outlined, color: Colors.white70),
              title: const Text('Thư viện ảnh',
                  style: TextStyle(color: Colors.white, fontSize: 15)),
              onTap: () {
                Navigator.pop(context);
                onPick(ImageSource.gallery);
              },
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.camera_alt_outlined, color: Colors.white70),
              title: const Text('Camera',
                  style: TextStyle(color: Colors.white, fontSize: 15)),
              onTap: () {
                Navigator.pop(context);
                onPick(ImageSource.camera);
              },
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Shimmer painter ──────────────────────────────────────────────────────────

class _ShimmerPainter extends CustomPainter {
  final double phase;
  const _ShimmerPainter({required this.phase});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    canvas.drawRect(
      Rect.fromLTWH(0, 0, w, h),
      Paint()..color = Colors.black.withValues(alpha: 0.6),
    );

    final cx = (-0.4 + phase * 1.8) * w;
    final hw = w * 0.35;
    final gradientRect = Rect.fromLTWH(cx - hw, 0, hw * 2, h);

    canvas.drawRect(
      Rect.fromLTWH(0, 0, w, h),
      Paint()
        ..shader = LinearGradient(
          begin: const Alignment(-1, -0.2),
          end: const Alignment(1, 0.2),
          colors: [
            Colors.transparent,
            Colors.white.withValues(alpha: 0.06),
            Colors.white.withValues(alpha: 0.18),
            Colors.white.withValues(alpha: 0.06),
            Colors.transparent,
          ],
          stops: const [0, 0.3, 0.5, 0.7, 1],
        ).createShader(gradientRect),
    );
  }

  @override
  bool shouldRepaint(_ShimmerPainter old) => old.phase != phase;
}

// ─── Isolate ──────────────────────────────────────────────────────────────────

Uint8List _isolateApplyMask(Map<String, dynamic> params) {
  final bytes = params['bytes'] as Uint8List;
  final mask = params['mask'] as Float32List;

  final src = img.decodeImage(bytes);
  if (src == null) throw Exception('Decode failed');

  final out = img.Image(width: src.width, height: src.height, numChannels: 4);
  final len = mask.length;

  for (int y = 0; y < src.height; y++) {
    for (int x = 0; x < src.width; x++) {
      final i = y * src.width + x;
      final a = i < len ? (mask[i] * 255).round().clamp(0, 255) : 0;
      final p = src.getPixel(x, y);
      out.setPixel(x, y, img.ColorRgba8(p.r.toInt(), p.g.toInt(), p.b.toInt(), a));
    }
  }

  return Uint8List.fromList(img.encodePng(out));
}
