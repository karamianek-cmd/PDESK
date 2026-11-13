import 'package:flutter_hbb/common/staff_auth.dart';
import 'package:flutter_hbb/common/widgets/network_help.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('super-admin is recognised case-insensitively', () {
    HelpApi.adminName = 'm.ghiasi';
    expect(HelpApi.isSuperAdmin, isTrue);
    HelpApi.adminName = 'M.GHIASI';
    expect(HelpApi.isSuperAdmin, isTrue);
  });

  test('other admins are not super-admin', () {
    HelpApi.adminName = 'alice';
    expect(HelpApi.isSuperAdmin, isFalse);
    HelpApi.adminName = '';
    expect(HelpApi.isSuperAdmin, isFalse);
    HelpApi.adminName = null;
    expect(HelpApi.isSuperAdmin, isFalse);
  });

  test('staff online flag defaults to offline when the server omits it', () {
    expect(const StaffEntry('u', 'f').online, isFalse);
    expect(const StaffEntry('u', 'f', online: true).online, isTrue);
  });
}