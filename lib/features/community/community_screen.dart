import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/api_service.dart';
import '../../core/enclosure_hash.dart';
import '../../core/speaker_profile.dart';
import '../auth/auth_controller.dart';
import '../auth/auth_screen.dart';
import '../ble/ble_controller.dart';
import '../dsp/dsp_compiler.dart';
import '../../core/audio_analyzer.dart';

class CommunityScreen extends ConsumerStatefulWidget {
  const CommunityScreen({super.key});
  @override
  ConsumerState<CommunityScreen> createState() => _CommunityScreenState();
}

class _CommunityScreenState extends ConsumerState<CommunityScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<dynamic> _presets = [];
  List<dynamic> _posts = [];
  bool _loadingPresets = true;
  bool _loadingPosts = true;
  String _presetSort = 'trending'; // trending | latest | match
  String _postCategory = 'all';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadPresets();
    _loadPosts();
  }

  @override
  void dispose() { _tabController.dispose(); super.dispose(); }

  /// 현재 스피커 프로파일로부터 인클로저 해시 계산
  String? _myHash() {
    final profile = ref.read(speakerProfileProvider);
    if (profile == null) return null;
    return EnclosureHash.fromProfile(
      volumeL:      profile.enclosureVolume,
      portLengthMm: profile.portLength,
      portDiamMm:   profile.portDiameter,
    );
  }

  Future<void> _loadPresets() async {
    setState(() => _loadingPresets = true);
    final Future<Map<String, dynamic>> request;
    if (_presetSort == 'trending') {
      request = ApiService.getTrending();
    } else if (_presetSort == 'match') {
      final hash = _myHash();
      request = ApiService.getPresets(hash: hash);
    } else {
      request = ApiService.getPresets();
    }
    final res = await request;
    if (res['status'] == 'ok') {
      setState(() { _presets = res['data'] ?? []; _loadingPresets = false; });
    } else {
      setState(() => _loadingPresets = false);
    }
  }

  Future<void> _loadPosts() async {
    setState(() => _loadingPosts = true);
    final res = await ApiService.getPosts(category: _postCategory);
    if (res['status'] == 'ok') {
      setState(() { _posts = res['data'] ?? []; _loadingPosts = false; });
    } else {
      setState(() => _loadingPosts = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    final ble = ref.watch(bleProvider);
    final connected = ble.connection == BleConnectionState.connected;

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: SafeArea(
        child: Column(
          children: [
            // 상단바
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: Row(
                children: [
                  const Text('COMMUNITY',
                      style: TextStyle(color: Colors.white, fontSize: 18,
                          fontWeight: FontWeight.w200, letterSpacing: 6)),
                  const Spacer(),
                  if (connected)
                    Container(
                      margin: const EdgeInsets.only(right: 12),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.white24, width: 0.5),
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: Text('● ${ble.deviceName ?? 'BLE'}',
                          style: const TextStyle(color: Colors.white38, fontSize: 9, letterSpacing: 1)),
                    ),
                  if (auth.isLoggedIn)
                    GestureDetector(
                      onTap: () => _showUploadDialog(context),
                      child: const Text('SHARE',
                          style: TextStyle(color: Colors.white54, fontSize: 10, letterSpacing: 2)),
                    )
                  else
                    GestureDetector(
                      onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => const AuthScreen())),
                      child: const Text('LOGIN',
                          style: TextStyle(color: Colors.white38, fontSize: 10, letterSpacing: 2)),
                    ),
                ],
              ),
            ),

            // 탭
            Container(
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: Colors.white12, width: 0.5)),
              ),
              child: TabBar(
                controller: _tabController,
                indicatorColor: Colors.white,
                indicatorWeight: 1,
                labelColor: Colors.white,
                unselectedLabelColor: Colors.white38,
                labelStyle: const TextStyle(fontSize: 10, letterSpacing: 2),
                tabs: const [
                  Tab(text: 'PRESETS'),
                  Tab(text: 'BOARD'),
                ],
              ),
            ),

            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _PresetsTab(
                    presets: _presets,
                    loading: _loadingPresets,
                    sort: _presetSort,
                    onSortChanged: (s) { setState(() => _presetSort = s); _loadPresets(); },
                    onRefresh: _loadPresets,
                    onDownload: _downloadAndApply,
                    onLike: _likePreset,
                    onComment: (p) => _showComments(context, p),
                  ),
                  _BoardTab(
                    posts: _posts,
                    loading: _loadingPosts,
                    category: _postCategory,
                    onCategoryChanged: (c) { setState(() => _postCategory = c); _loadPosts(); },
                    onRefresh: _loadPosts,
                    onTap: (p) => _showPost(context, p),
                    onWrite: auth.isLoggedIn
                        ? () => _showWriteDialog(context)
                        : () => Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => const AuthScreen())),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _likePreset(Map<String, dynamic> preset) async {
    final auth = ref.read(authProvider);
    if (!auth.isLoggedIn) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('로그인 후 좋아요 가능합니다.')));
      return;
    }
    final res = await ApiService.likePreset(preset['id']);
    if (res['status'] == 'ok') {
      setState(() {
        final idx = _presets.indexOf(preset);
        if (idx >= 0) {
          _presets[idx] = Map.from(preset)
            ..['likes'] = (preset['likes'] ?? 0) + (res['liked'] == true ? 1 : -1);
        }
      });
    }
  }

  Future<void> _downloadAndApply(Map<String, dynamic> preset) async {
    final auth = ref.read(authProvider);
    if (!auth.isLoggedIn) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('로그인 후 다운로드할 수 있습니다.')));
      return;
    }
    final fps = preset['fps_json'] as List?;
    if (fps == null || fps.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('필터 데이터가 없는 프리셋입니다.')));
      return;
    }
    final peaks = fps.map((f) => ResonancePeak(
      frequency: (f['frequency'] ?? f['f'] ?? 1000).toDouble(),
      gain: (f['gain'] ?? f['g'] ?? -6).toDouble(),
      q: (f['q'] ?? 2.0).toDouble(),
    )).toList();
    final packets = DspCompiler.compileAll(peaks);
    final ble = ref.read(bleProvider);
    if (ble.connection != BleConnectionState.connected) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(
            '${preset['title']} 다운로드 완료\nDSP 적용: CONNECT 탭에서 연결 후 재시도'),
          duration: const Duration(seconds: 4)));
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${preset['title']} DSP 적용 중...')));
    final success = await ref.read(bleProvider.notifier).sendPackets(packets);
    if (!context.mounted) return;
    // ignore: use_build_context_synchronously
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(success
          ? '✓ ${preset['title']} 적용 완료'
          : '전송 실패 — BLE 연결 확인'),
    ));
  }

  void _showComments(BuildContext context, Map<String, dynamic> preset) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF111111),
      isScrollControlled: true,
      builder: (_) => _CommentsSheet(preset: preset),
    );
  }

  void _showPost(BuildContext context, Map<String, dynamic> post) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF111111),
      isScrollControlled: true,
      builder: (_) => _PostSheet(post: post),
    );
  }

  void _showWriteDialog(BuildContext context) {
    final titleCtrl = TextEditingController();
    final contentCtrl = TextEditingController();
    String category = 'general';
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF111111),
      isScrollControlled: true,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setS) => Padding(
          padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom,
              left: 24, right: 24, top: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('글쓰기',
                  style: TextStyle(color: Colors.white, fontSize: 14, letterSpacing: 2)),
              const SizedBox(height: 16),
              // 카테고리
              Wrap(
                spacing: 8,
                children: [
                  for (final c in [
                    ['general', '자유'],
                    ['tip', '튜닝팁'],
                    ['review', '리뷰'],
                    ['qna', 'Q&A'],
                  ])
                    GestureDetector(
                      onTap: () => setS(() => category = c[0]),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        decoration: BoxDecoration(
                          border: Border.all(
                              color: category == c[0] ? Colors.white : Colors.white24,
                              width: 0.5),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(c[1],
                            style: TextStyle(
                              color: category == c[0] ? Colors.white : Colors.white38,
                              fontSize: 11,
                            )),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              _DialogField(label: '제목', controller: titleCtrl),
              const SizedBox(height: 8),
              TextField(
                controller: contentCtrl,
                maxLines: 4,
                style: const TextStyle(color: Colors.white, fontSize: 13),
                decoration: const InputDecoration(
                  labelText: '내용',
                  labelStyle: TextStyle(color: Colors.white38, fontSize: 10),
                  enabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: Colors.white24, width: 0.5)),
                  focusedBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: Colors.white, width: 0.5)),
                  contentPadding: EdgeInsets.all(12),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () async {
                        if (titleCtrl.text.trim().isEmpty) return;
                        Navigator.pop(context);
                        final res = await ApiService.createPost(
                          title: titleCtrl.text.trim(),
                          content: contentCtrl.text.trim(),
                          category: category,
                        );
                        if (!context.mounted) return;
                        if (res['status'] == 'ok') {
                          _loadPosts();
                          ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('게시글이 등록됐습니다.')));
                        }
                      },
                      child: Container(
                        height: 44,
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.white),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Center(
                          child: Text('등록',
                              style: TextStyle(color: Colors.white, fontSize: 12, letterSpacing: 2)),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  void _showUploadDialog(BuildContext context) {
    final titleCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    final roomCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF111111),
        title: const Text('프리셋 공유',
            style: TextStyle(color: Colors.white, fontSize: 14, letterSpacing: 2)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _DialogField(label: 'TITLE', controller: titleCtrl),
            const SizedBox(height: 12),
            _DialogField(label: 'DESCRIPTION', controller: descCtrl),
            const SizedBox(height: 12),
            _DialogField(label: 'ROOM TAG', controller: roomCtrl),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context),
              child: const Text('취소', style: TextStyle(color: Colors.white38))),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              final res = await ApiService.uploadPreset(
                title: titleCtrl.text.trim(),
                description: descCtrl.text.trim(),
                fps: [], roomTag: roomCtrl.text.trim(),
                enclosureHash: _myHash(),
              );
              if (!context.mounted) return;
              if (res['status'] == 'ok') {
                _loadPresets();
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('프리셋이 공유됐습니다!')));
              }
            },
            child: const Text('공유', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}

// ── PRESETS 탭 ────────────────────────────────────────
class _PresetsTab extends StatelessWidget {
  final List<dynamic> presets;
  final bool loading;
  final String sort;
  final Function(String) onSortChanged;
  final Future<void> Function() onRefresh;
  final Function(Map<String, dynamic>) onDownload;
  final Function(Map<String, dynamic>) onLike;
  final Function(Map<String, dynamic>) onComment;

  const _PresetsTab({
    required this.presets, required this.loading, required this.sort,
    required this.onSortChanged, required this.onRefresh,
    required this.onDownload, required this.onLike, required this.onComment,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // 정렬 버튼
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 8),
          child: Row(
            children: [
              _SortBtn('인기순', sort == 'trending', () => onSortChanged('trending')),
              const SizedBox(width: 8),
              _SortBtn('최신순', sort == 'latest', () => onSortChanged('latest')),
              const SizedBox(width: 8),
              _SortBtn('내 스피커', sort == 'match', () => onSortChanged('match')),
            ],
          ),
        ),
        Expanded(
          child: loading
              ? const Center(child: CircularProgressIndicator(color: Colors.white24, strokeWidth: 1))
              : presets.isEmpty
                  ? const Center(child: Text('프리셋이 없습니다.',
                        style: TextStyle(color: Colors.white38, fontSize: 13)))
                  : RefreshIndicator(
                      onRefresh: onRefresh,
                      color: Colors.white,
                      backgroundColor: const Color(0xFF111111),
                      child: ListView.separated(
                        padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
                        itemCount: presets.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (_, i) => _PresetCard(
                          preset: presets[i],
                          onDownload: () => onDownload(presets[i]),
                          onLike: () => onLike(presets[i]),
                          onComment: () => onComment(presets[i]),
                        ),
                      ),
                    ),
        ),
      ],
    );
  }
}

class _SortBtn extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _SortBtn(this.label, this.selected, this.onTap);

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        border: Border.all(color: selected ? Colors.white : Colors.white24, width: 0.5),
        borderRadius: BorderRadius.circular(20),
        color: selected ? Colors.white.withValues(alpha: 0.05) : Colors.transparent,
      ),
      child: Text(label,
          style: TextStyle(
            color: selected ? Colors.white : Colors.white38, fontSize: 11)),
    ),
  );
}

class _PresetCard extends StatelessWidget {
  final Map<String, dynamic> preset;
  final VoidCallback onDownload;
  final VoidCallback onLike;
  final VoidCallback onComment;
  const _PresetCard({required this.preset, required this.onDownload,
      required this.onLike, required this.onComment});

  @override
  Widget build(BuildContext context) {
    final fps = preset['fps_json'] as List? ?? [];
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.white12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(preset['title'] ?? '',
                    style: const TextStyle(color: Colors.white, fontSize: 15)),
              ),
              GestureDetector(
                onTap: onDownload,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.white24),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text('GET',
                      style: TextStyle(color: Colors.white, fontSize: 10, letterSpacing: 2)),
                ),
              ),
            ],
          ),
          if (preset['description'] != null && preset['description'].isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(preset['description'],
                style: const TextStyle(color: Colors.white38, fontSize: 12)),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              if (preset['room_tag'] != null) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.white10, borderRadius: BorderRadius.circular(4)),
                  child: Text(preset['room_tag'],
                      style: const TextStyle(color: Colors.white54, fontSize: 10)),
                ),
                const SizedBox(width: 8),
              ],
              Text('${fps.length}밴드',
                  style: const TextStyle(color: Colors.white24, fontSize: 10)),
              const Spacer(),
              // 좋아요
              GestureDetector(
                onTap: onLike,
                child: Row(
                  children: [
                    const Icon(Icons.favorite_border, color: Colors.white38, size: 14),
                    const SizedBox(width: 3),
                    Text('${preset['likes'] ?? 0}',
                        style: const TextStyle(color: Colors.white38, fontSize: 10)),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              // 댓글
              GestureDetector(
                onTap: onComment,
                child: const Icon(Icons.chat_bubble_outline, color: Colors.white38, size: 14),
              ),
              const SizedBox(width: 12),
              Text('↓${preset['downloads'] ?? 0}',
                  style: const TextStyle(color: Colors.white24, fontSize: 10)),
              const SizedBox(width: 8),
              Text('by ${preset['nickname'] ?? ''}',
                  style: const TextStyle(color: Colors.white24, fontSize: 10)),
            ],
          ),
        ],
      ),
    );
  }
}

// ── BOARD 탭 ────────────────────────────────────────
class _BoardTab extends StatelessWidget {
  final List<dynamic> posts;
  final bool loading;
  final String category;
  final Function(String) onCategoryChanged;
  final Future<void> Function() onRefresh;
  final Function(Map<String, dynamic>) onTap;
  final VoidCallback onWrite;

  const _BoardTab({
    required this.posts, required this.loading, required this.category,
    required this.onCategoryChanged, required this.onRefresh,
    required this.onTap, required this.onWrite,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // 카테고리 필터
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 8),
          child: Row(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final c in [
                        ['all', '전체'],
                        ['tip', '튜닝팁'],
                        ['review', '리뷰'],
                        ['qna', 'Q&A'],
                        ['general', '자유'],
                      ])
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: _SortBtn(c[1], category == c[0],
                              () => onCategoryChanged(c[0])),
                        ),
                    ],
                  ),
                ),
              ),
              GestureDetector(
                onTap: onWrite,
                child: const Icon(Icons.edit_outlined, color: Colors.white54, size: 18),
              ),
            ],
          ),
        ),
        Expanded(
          child: loading
              ? const Center(child: CircularProgressIndicator(color: Colors.white24, strokeWidth: 1))
              : posts.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('게시글이 없습니다.',
                              style: TextStyle(color: Colors.white38, fontSize: 13)),
                          const SizedBox(height: 16),
                          GestureDetector(
                            onTap: onWrite,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 20, vertical: 10),
                              decoration: BoxDecoration(
                                border: Border.all(color: Colors.white38),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Text('첫 글 쓰기',
                                  style: TextStyle(color: Colors.white, fontSize: 12)),
                            ),
                          ),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: onRefresh,
                      color: Colors.white,
                      backgroundColor: const Color(0xFF111111),
                      child: ListView.separated(
                        padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
                        itemCount: posts.length,
                        separatorBuilder: (_, __) =>
                            const Divider(color: Colors.white12, height: 1),
                        itemBuilder: (_, i) => _PostRow(
                          post: posts[i],
                          onTap: () => onTap(posts[i]),
                        ),
                      ),
                    ),
        ),
      ],
    );
  }
}

class _PostRow extends StatelessWidget {
  final Map<String, dynamic> post;
  final VoidCallback onTap;
  const _PostRow({required this.post, required this.onTap});

  String get _categoryLabel {
    switch (post['category']) {
      case 'tip': return '튜닝팁';
      case 'review': return '리뷰';
      case 'qna': return 'Q&A';
      default: return '자유';
    }
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.white10, borderRadius: BorderRadius.circular(3)),
            child: Text(_categoryLabel,
                style: const TextStyle(color: Colors.white38, fontSize: 9)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(post['title'] ?? '',
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text(post['nickname'] ?? '',
                        style: const TextStyle(color: Colors.white38, fontSize: 10)),
                    const SizedBox(width: 8),
                    const Icon(Icons.favorite_border, color: Colors.white24, size: 10),
                    const SizedBox(width: 2),
                    Text('${post['likes'] ?? 0}',
                        style: const TextStyle(color: Colors.white24, fontSize: 10)),
                    const SizedBox(width: 8),
                    const Icon(Icons.chat_bubble_outline, color: Colors.white24, size: 10),
                    const SizedBox(width: 2),
                    Text('${post['comment_count'] ?? 0}',
                        style: const TextStyle(color: Colors.white24, fontSize: 10)),
                  ],
                ),
              ],
            ),
          ),
          Text('조회 ${post['views'] ?? 0}',
              style: const TextStyle(color: Colors.white24, fontSize: 9)),
        ],
      ),
    ),
  );
}

// ── 댓글 시트 ────────────────────────────────────────
class _CommentsSheet extends ConsumerStatefulWidget {
  final Map<String, dynamic> preset;
  const _CommentsSheet({required this.preset});

  @override
  ConsumerState<_CommentsSheet> createState() => _CommentsSheetState();
}

class _CommentsSheetState extends ConsumerState<_CommentsSheet> {
  List<dynamic> _comments = [];
  bool _loading = true;
  final _ctrl = TextEditingController();

  @override
  void initState() { super.initState(); _load(); }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  Future<void> _load() async {
    final res = await ApiService.getComments(widget.preset['id']);
    if (res['status'] == 'ok') {
      setState(() { _comments = res['data'] ?? []; _loading = false; });
    } else {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      maxChildSize: 0.9,
      minChildSize: 0.3,
      expand: false,
      builder: (_, scrollCtrl) => Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: Text(widget.preset['title'] ?? '',
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: const Icon(Icons.close, color: Colors.white38, size: 18),
                ),
              ],
            ),
          ),
          const Divider(color: Colors.white12, height: 1),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(
                    color: Colors.white24, strokeWidth: 1))
                : _comments.isEmpty
                    ? const Center(child: Text('첫 댓글을 남겨보세요.',
                          style: TextStyle(color: Colors.white38, fontSize: 13)))
                    : ListView.separated(
                        controller: scrollCtrl,
                        padding: const EdgeInsets.all(16),
                        itemCount: _comments.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (_, i) => _CommentRow(comment: _comments[i]),
                      ),
          ),
          if (auth.isLoggedIn)
            Container(
              padding: EdgeInsets.only(
                  left: 16, right: 16, bottom: MediaQuery.of(context).viewInsets.bottom + 16,
                  top: 8),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: Colors.white12, width: 0.5))),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _ctrl,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      decoration: const InputDecoration(
                        hintText: '댓글 입력...',
                        hintStyle: TextStyle(color: Colors.white24),
                        border: InputBorder.none,
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: () async {
                      if (_ctrl.text.trim().isEmpty) return;
                      await ApiService.addComment(widget.preset['id'], _ctrl.text.trim());
                      _ctrl.clear();
                      _load();
                    },
                    child: const Icon(Icons.send, color: Colors.white54, size: 20),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _CommentRow extends StatelessWidget {
  final Map<String, dynamic> comment;
  const _CommentRow({required this.comment});

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      CircleAvatar(
        radius: 14,
        backgroundColor: Colors.white12,
        child: Text((comment['nickname'] ?? '?')[0].toUpperCase(),
            style: const TextStyle(color: Colors.white54, fontSize: 11)),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(comment['nickname'] ?? '',
                style: const TextStyle(color: Colors.white54, fontSize: 11)),
            const SizedBox(height: 3),
            Text(comment['content'] ?? '',
                style: const TextStyle(color: Colors.white, fontSize: 13)),
          ],
        ),
      ),
    ],
  );
}

// ── 게시글 상세 시트 ──────────────────────────────────
class _PostSheet extends ConsumerStatefulWidget {
  final Map<String, dynamic> post;
  const _PostSheet({required this.post});

  @override
  ConsumerState<_PostSheet> createState() => _PostSheetState();
}

class _PostSheetState extends ConsumerState<_PostSheet> {
  Map<String, dynamic>? _detail;
  bool _loading = true;
  final _ctrl = TextEditingController();

  @override
  void initState() { super.initState(); _load(); }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  Future<void> _load() async {
    final res = await ApiService.getPost(widget.post['id']);
    if (res['status'] == 'ok') {
      setState(() { _detail = res['data']; _loading = false; });
    } else {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    return DraggableScrollableSheet(
      initialChildSize: 0.8,
      maxChildSize: 0.95,
      minChildSize: 0.5,
      expand: false,
      builder: (_, scrollCtrl) => Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: Text(widget.post['title'] ?? '',
                      style: const TextStyle(color: Colors.white, fontSize: 14,
                          fontWeight: FontWeight.w400)),
                ),
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: const Icon(Icons.close, color: Colors.white38, size: 18),
                ),
              ],
            ),
          ),
          const Divider(color: Colors.white12, height: 1),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(
                    color: Colors.white24, strokeWidth: 1))
                : ListView(
                    controller: scrollCtrl,
                    padding: const EdgeInsets.all(16),
                    children: [
                      // 작성자 + 날짜
                      Row(
                        children: [
                          Text(_detail?['nickname'] ?? '',
                              style: const TextStyle(color: Colors.white54, fontSize: 12)),
                          const Spacer(),
                          Text(_detail?['created_at']?.toString().substring(0, 10) ?? '',
                              style: const TextStyle(color: Colors.white24, fontSize: 11)),
                        ],
                      ),
                      const SizedBox(height: 16),
                      // 본문
                      Text(_detail?['content'] ?? '',
                          style: const TextStyle(color: Colors.white, fontSize: 14, height: 1.7)),
                      const SizedBox(height: 16),
                      // 좋아요
                      GestureDetector(
                        onTap: () async {
                          await ApiService.likePost(widget.post['id']);
                          _load();
                        },
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.favorite_border, color: Colors.white38, size: 16),
                            const SizedBox(width: 4),
                            Text('${_detail?['likes'] ?? 0}',
                                style: const TextStyle(color: Colors.white38, fontSize: 12)),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      const Divider(color: Colors.white12),
                      const SizedBox(height: 8),
                      Text('댓글 ${(_detail?['comments'] as List? ?? []).length}',
                          style: const TextStyle(color: Colors.white38, fontSize: 11,
                              letterSpacing: 1)),
                      const SizedBox(height: 12),
                      for (final c in (_detail?['comments'] as List? ?? []))
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _CommentRow(comment: c),
                        ),
                    ],
                  ),
          ),
          if (auth.isLoggedIn)
            Container(
              padding: EdgeInsets.only(
                  left: 16, right: 16,
                  bottom: MediaQuery.of(context).viewInsets.bottom + 16,
                  top: 8),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: Colors.white12, width: 0.5))),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _ctrl,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      decoration: const InputDecoration(
                        hintText: '댓글 입력...',
                        hintStyle: TextStyle(color: Colors.white24),
                        border: InputBorder.none,
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: () async {
                      if (_ctrl.text.trim().isEmpty) return;
                      await ApiService.addPostComment(widget.post['id'], _ctrl.text.trim());
                      _ctrl.clear();
                      _load();
                    },
                    child: const Icon(Icons.send, color: Colors.white54, size: 20),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _DialogField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  const _DialogField({required this.label, required this.controller});

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: const TextStyle(color: Colors.white38, fontSize: 9, letterSpacing: 2)),
      TextField(
        controller: controller,
        style: const TextStyle(color: Colors.white, fontSize: 13),
        decoration: const InputDecoration(
          enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
          focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white)),
          contentPadding: EdgeInsets.symmetric(vertical: 6),
        ),
      ),
    ],
  );
}
