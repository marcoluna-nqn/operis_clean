import 'dart:ui';
import 'package:flutter/cupertino.dart';

class GlassButton extends StatelessWidget {
  const GlassButton({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    required this.onPressed,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: CupertinoButton(
          padding: const EdgeInsets.all(14),
          color: const Color(0x22FFFFFF),
          onPressed: onPressed,
          child: Row(
            children: [
              Icon(icon,
                  color: CupertinoColors.white.withOpacity(.9), size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                          color: CupertinoColors.white,
                        )),
                    if (subtitle != null)
                      Text(subtitle!,
                          style: TextStyle(
                            fontSize: 13,
                            color: CupertinoColors.white.withOpacity(.7),
                          )),
                  ],
                ),
              ),
              const Icon(CupertinoIcons.chevron_right,
                  size: 18, color: CupertinoColors.systemGrey),
            ],
          ),
        ),
      ),
    );
  }
}
