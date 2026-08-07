import 'package:flutter/material.dart';

class AppIcon extends StatelessWidget {
  const AppIcon({
    required this.url,
    this.size = 56,
    this.borderRadius = 12,
    super.key,
  });

  final String url;
  final double size;
  final double borderRadius;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(borderRadius),
    child: url.isEmpty
        ? _placeholder(context)
        : Image.network(
            url,
            width: size,
            height: size,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) => _placeholder(context),
          ),
  );

  Widget _placeholder(BuildContext context) => Container(
    width: size,
    height: size,
    color: Theme.of(context).colorScheme.surfaceContainerHighest,
    child: const Icon(Icons.android),
  );
}
