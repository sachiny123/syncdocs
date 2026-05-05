import 'package:diff_match_patch/diff_match_patch.dart';
void main() {
  final dmp = DiffMatchPatch();
  final patches = dmp.patch('hello', 'hello world');
  print(patchToText(patches));
}
