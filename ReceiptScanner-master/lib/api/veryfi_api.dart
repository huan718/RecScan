import 'dart:convert';
import 'dart:io';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

class ReceiptData {
  final String vendor;
  final DateTime? date;
  final double? total;

  const ReceiptData({required this.vendor, this.date, this.total});

  factory ReceiptData.fromVeryfi(Map<String, dynamic> json) {
    return ReceiptData(
      vendor: json['vendor']['name'] ?? '',
      date: json['date'] != null ? DateTime.parse(json['date']) : null,
      total: (json['total'] ?? 0).toDouble(),
    );
  }
}

class VeryfiApi {
  VeryfiApi()
      : _cid = dotenv.env['VERYFI_CLIENT_ID'],
        _user = dotenv.env['VERYFI_USERNAME'],
        _key = dotenv.env['VERYFI_API_KEY'];

  final String? _cid;
  final String? _user;
  final String? _key;

  static const _endpoint =
      'https://api.veryfi.com/api/v8/partner/documents';

  Future<ReceiptData> scanReceipt(String imagePath) async {
    if (_cid == null || _user == null || _key == null) {
      throw StateError(
          'VERYFI_CLIENT_ID / USERNAME / API_KEY missing in .env');
    }

    final req = http.MultipartRequest('POST', Uri.parse(_endpoint))
      ..headers.addAll({
        'CLIENT-ID': _cid!,
        // 👇 correct auth format
        'AUTHORIZATION': 'apikey $_user:$_key',
        'Accept': 'application/json',
      })
      ..files.add(await http.MultipartFile.fromPath(
        'file',
        imagePath,
        contentType: MediaType('image', 'jpeg'),
      ));

    final resp = await http.Response.fromStream(await req.send());
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
       // real error
       throw HttpException('Veryfi error ${resp.statusCode}: ${resp.body}');
     }
    return ReceiptData.fromVeryfi(json.decode(resp.body));
  }
}