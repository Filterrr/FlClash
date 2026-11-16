import 'package:flutter/material.dart';
import '../common/common.dart';

class NullStatus extends StatelessWidget {
  final String label;
  final IconData? iconData;
  final String? desc;
  final Widget? action;

  const NullStatus({
    super.key,
    required this.label,
    this.iconData,
    this.desc,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    if (iconData == null && desc == null && action == null) {
      return Center(
        child: Text(
          label,
          style: Theme.of(context).textTheme.titleMedium?.toBold,
        ),
      );
    }
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (iconData != null)
              Container(
                width: 92,
                height: 92,
                decoration: BoxDecoration(
                  color: colorScheme.primary.opacity10,
                  borderRadius: BorderRadius.circular(28),
                ),
                child: Icon(
                  iconData,
                  size: 40,
                  color: colorScheme.primary,
                ),
              ),
            const SizedBox(
              height: 20,
            ),
            Text(
              label,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            if (desc != null) ...[
              const SizedBox(
                height: 8,
              ),
              Text(
                desc!,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      height: 1.5,
                    ),
              ),
            ],
            if (action != null) ...[
              const SizedBox(
                height: 22,
              ),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}
