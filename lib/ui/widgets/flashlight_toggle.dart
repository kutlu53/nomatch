import 'package:flutter/material.dart';

/// Yazısız, minimalist flaş ışığı toggle switchi.
/// Sol üst köşede konumlanmak için tasarlandı.
class FlashlightToggle extends StatelessWidget {
  final bool isOn;
  final VoidCallback onToggle;

  const FlashlightToggle({
    super.key,
    required this.isOn,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onToggle,
      child: Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          color: isOn 
            ? const Color(0xFFFFD700).withOpacity(0.3) // Açıkken sarımtırak
            : Colors.white.withOpacity(0.15), // Kapalıyken hafif beyaz
          shape: BoxShape.circle,
          border: Border.all(
            color: isOn 
              ? const Color(0xFFFFD700) // Altın sarısı
              : Colors.white.withOpacity(0.4),
            width: 2,
          ),
          boxShadow: isOn ? [
            BoxShadow(
              color: const Color(0xFFFFD700).withOpacity(0.5),
              blurRadius: 16,
              spreadRadius: 2,
            ),
          ] : null,
        ),
        child: Icon(
          Icons.toggle_on_outlined,
          color: isOn 
            ? const Color(0xFFFFD700) 
            : Colors.white.withOpacity(0.6),
          size: 32,
        ),
      ),
    );
  }
}
