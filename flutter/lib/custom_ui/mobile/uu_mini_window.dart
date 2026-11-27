import 'package:flutter/material.dart';
import 'package:flutter_hbb/models/model.dart';

import '../design/uu_tokens.dart';
import '../uu_defaults.dart';
import 'uu_mobile_home.dart';

/// 把当前远控画面收进悬浮小窗，叠在 App 首页上继续实时刷新。
Future<void> enterUuMiniWindow(BuildContext context, String id, FFI ffi) {
  return Navigator.of(context).push<void>(
    PageRouteBuilder<void>(
      pageBuilder: (_, __, ___) => UuMiniWindowPage(id: id, ffi: ffi),
      transitionsBuilder: (_, animation, __, child) =>
          FadeTransition(opacity: animation, child: child),
      transitionDuration: const Duration(milliseconds: 180),
    ),
  );
}

class UuMiniWindowPage extends StatefulWidget {
  const UuMiniWindowPage({super.key, required this.id, required this.ffi});

  final String id;
  final FFI ffi;

  @override
  State<UuMiniWindowPage> createState() => _UuMiniWindowPageState();
}

class _UuMiniWindowPageState extends State<UuMiniWindowPage> {
  Offset? _offset;

  @override
  void initState() {
    super.initState();
    uuMiniWindowOpen.value = true;
  }

  @override
  void dispose() {
    uuMiniWindowOpen.value = false;
    super.dispose();
  }

  void _restore() {
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    UuColors.apply(context);
    final media = MediaQuery.of(context);
    final size = media.size;
    final winW = (size.width * 0.46).clamp(160.0, 260.0);
    final winH = winW * 10 / 16;
    final minX = 12.0;
    final maxX = size.width - winW - minX;
    final minY = media.padding.top + 12;
    final maxY = size.height - winH - media.padding.bottom - 12;
    final defaultPos = Offset(maxX, maxY - 70);
    final pos = _offset ?? defaultPos;
    return Scaffold(
      backgroundColor: UuColors.background,
      body: Stack(
        children: [
          const UuMobileHome(),
          Positioned(
            left: pos.dx.clamp(minX, maxX),
            top: pos.dy.clamp(minY, maxY),
            width: winW,
            height: winH,
            child: GestureDetector(
              onTap: _restore,
              onPanUpdate: (details) {
                setState(() {
                  final base = _offset ?? defaultPos;
                  _offset = Offset(
                    (base.dx + details.delta.dx).clamp(minX, maxX),
                    (base.dy + details.delta.dy).clamp(minY, maxY),
                  );
                });
              },
              child: _MiniRemoteView(ffi: widget.ffi, onRestore: _restore),
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniRemoteView extends StatelessWidget {
  const _MiniRemoteView({required this.ffi, required this.onRestore});

  final FFI ffi;
  final VoidCallback onRestore;

  @override
  Widget build(BuildContext context) {
    final hostname = ffi.ffiModel.pi.hostname;
    return Container(
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white24),
        boxShadow: const [
          BoxShadow(
            color: Color(0x59000000),
            blurRadius: 18,
            offset: Offset(0, 6),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ListenableBuilder(
            listenable: ffi.imageModel,
            builder: (_, __) {
              final image = ffi.imageModel.image;
              if (image == null) {
                return const ColoredBox(color: Colors.black);
              }
              return FittedBox(
                fit: BoxFit.contain,
                child: RawImage(image: image),
              );
            },
          ),
          Positioned(
            right: 6,
            top: 6,
            child: Material(
              color: Colors.black.withOpacity(0.45),
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: onRestore,
                child: const Padding(
                  padding: EdgeInsets.all(6),
                  child:
                      Icon(Icons.open_in_full, size: 15, color: Colors.white),
                ),
              ),
            ),
          ),
          if (hostname.isNotEmpty)
            Positioned(
              left: 8,
              bottom: 6,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.45),
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text(
                  hostname,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
