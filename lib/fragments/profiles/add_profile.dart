import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/pages/scan.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/material.dart';

class AddProfile extends StatelessWidget {
  final BuildContext context;

  const AddProfile({
    super.key,
    required this.context,
  });

  _handleAddProfileFormFile() async {
    globalState.appController.addProfileFormFile();
  }

  _handleAddProfileFormURL(String url) async {
    globalState.appController.addProfileFormURL(url);
  }

  _toScan() async {
    if (system.isDesktop) {
      globalState.appController.addProfileFormQrCode();
      return;
    }
    final url = await BaseNavigator.push(
      context,
      const ScanPage(),
    );
    if (url != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _handleAddProfileFormURL(url);
      });
    }
  }

  _toAdd() async {
    final url = await globalState.showCommonDialog<String>(
      child: const URLFormDialog(),
    );
    if (url != null) {
      _handleAddProfileFormURL(url);
    }
  }

  @override
  Widget build(context) {
    return ListView(
      padding: const EdgeInsets.only(top: 8),
      children: [
        SettingsSection(
          label: appLocalizations.importMethod,
          dividerIndentWithIcon: true,
          children: [
            ListItem(
              iconData: Icons.qr_code_2,
              title: Text(appLocalizations.qrcode),
              subtitle: Text(appLocalizations.qrcodeDesc),
              showArrow: true,
              onTap: _toScan,
            ),
            ListItem(
              iconData: Icons.upload_file_outlined,
              title: Text(appLocalizations.file),
              subtitle: Text(appLocalizations.fileDesc),
              showArrow: true,
              onTap: _handleAddProfileFormFile,
            ),
            ListItem(
              iconData: Icons.cloud_download_outlined,
              title: Text(appLocalizations.url),
              subtitle: Text(appLocalizations.urlDesc),
              showArrow: true,
              onTap: _toAdd,
            ),
          ],
        ),
        SettingsNote(
          text: appLocalizations.addProfileTip,
        ),
        const SettingsBottomSpace(),
      ],
    );
  }
}

class URLFormDialog extends StatefulWidget {
  const URLFormDialog({super.key});

  @override
  State<URLFormDialog> createState() => _URLFormDialogState();
}

class _URLFormDialogState extends State<URLFormDialog> {
  final urlController = TextEditingController();

  _handleAddProfileFormURL() async {
    final url = urlController.value.text;
    if (url.isEmpty) return;
    Navigator.of(context).pop<String>(url);
  }

  @override
  void dispose() {
    urlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(appLocalizations.importFromURL),
      content: SizedBox(
        width: dialogCommonWidth,
        child: Wrap(
          runSpacing: 16,
          children: [
            TextField(
              autofocus: true,
              maxLines: 5,
              minLines: 1,
              controller: urlController,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.link),
                border: const OutlineInputBorder(),
                labelText: appLocalizations.url,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _handleAddProfileFormURL,
          child: Text(appLocalizations.submit),
        )
      ],
    );
  }
}
