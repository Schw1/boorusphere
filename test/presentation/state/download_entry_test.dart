import 'package:boorusphere/data/repository/downloads/entity/download_entry.dart';
import 'package:boorusphere/presentation/provider/download/download_state.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../utils/fake_data.dart';

void main() {
  final posts = getSamplePosts().toList();

  test('a download is found after score and tags of its post changed', () {
    final entries = [
      DownloadEntry(id: 'a', post: posts[0], dest: 'a.jpg'),
      DownloadEntry(id: 'b', post: posts[1], dest: 'b.jpg'),
    ];
    final later = posts[1].copyWith(
      score: posts[1].score + 10,
      tags: [...posts[1].tags, 'new_tag'],
    );

    expect(entries.getByPost(later).id, 'b');
    expect(entries.getByPost(posts[0]).id, 'a');
    expect(entries.getByPost(posts[2]), DownloadEntry.empty);
    expect(
      entries.getByPost(posts[0].copyWith(serverId: 'Elsewhere')),
      DownloadEntry.empty,
    );
  });
}
