import 'dart:io';
import 'package:be_core/be_core.dart';
import 'package:crm_app/crm_service.dart';

void main(List<String> args) async {
  final storagePath = args.isNotEmpty ? args[0] : '${Directory.current.path}/crm_data.json';
  final service = await CrmService.init(storagePath);
  final server = StandardAppServer(schema: service.schema, store: service.store);
  await server.start();
}
