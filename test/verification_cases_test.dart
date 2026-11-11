import 'dart:typed_data';

import 'package:doggo/data/demo/demo_repository.dart';
import 'package:doggo/data/models/profile.dart';
import 'package:doggo/data/models/sitter_case.dart';
import 'package:doggo/data/repositories/repository.dart';
import 'package:flutter_test/flutter_test.dart';

const natalia = 'a1000000-0000-4000-8000-000000000011';
const ricardo = 'a1000000-0000-4000-8000-000000000012';
const meet = 'https://meet.google.com/abc-defg-hij';

/// Fase 13: casos de verificación en la demo (mismas reglas que la sección 11
/// de supabase/schema.sql).
void main() {
  late DemoRepository r;
  final nextWeek = DateTime.now().add(const Duration(days: 7));

  Future<void> as(String email, [String password = demoPassword]) async {
    await r.signOut();
    await r.signIn(email: email, password: password);
  }

  Future<SitterCase> caseOf(String id) async => (await r.fetchPendingSitters())
      .singleWhere((p) => p.user.id == id)
      .sitterCase!;

  setUp(() async {
    r = DemoRepository();
    await r.signIn(email: 'admin@doggo.app', password: demoPassword);
  });

  test(
    'los cuidadores en revisión del seed son casos de la única admin',
    () async {
      for (final id in [natalia, ricardo]) {
        final c = await caseOf(id);
        expect(c.assignedAdminId, 'demo-admin');
        expect(c.assignedAdminName, 'Ana Admin');
        expect(c.stage, CaseStage.fresh);
      }
      expect(await r.watchMyNewCases().first, 2);
    },
  );

  test('un cuidador nuevo ve su caso y quién lo lleva', () async {
    await r.signOut();
    await r.signUp(
      email: 'nuevo@t.test',
      password: 'secreto1',
      fullName: 'Nico Nuevo',
      role: UserRole.sitter,
      acceptedTerms: true,
    );
    final mine = await r.watchMyCase().first;
    expect(mine?.assignedAdminName, 'Ana Admin');
    expect(mine?.stage, CaseStage.fresh);
  });

  test('los casos se reparten al admin con menos casos', () async {
    await as('superadmin@doggo.app');
    final owner = (await r.searchUsers(query: 'dueno@doggo.app')).single;
    await r.setAdmin(owner.id, makeAdmin: true);
    for (var i = 0; i < 3; i++) {
      await r.signOut();
      await r.signUp(
        email: 's$i@t.test',
        password: 'secreto1',
        fullName: 'Sitter $i',
        role: UserRole.sitter,
        acceptedTerms: true,
      );
    }
    await as('superadmin@doggo.app');
    final byAdmin = <String?, int>{};
    for (final p in await r.fetchPendingSitters()) {
      final id = p.sitterCase!.assignedAdminId;
      byAdmin[id] = (byAdmin[id] ?? 0) + 1;
    }
    // Ana tenía 2; Daniela (nueva admin) recibe los nuevos hasta empatar.
    expect(byAdmin['demo-admin'], greaterThanOrEqualTo(2));
    expect(byAdmin[owner.id], greaterThanOrEqualTo(2));
    expect(byAdmin.values.fold(0, (a, b) => a + b), 5);
    expect(byAdmin.containsKey('demo-superadmin'), isFalse);
  });

  test(
    'reunión: se agenda, el cuidador la confirma, se marca hecha y se aprueba',
    () async {
      expect(
        () => r.scheduleMeeting(
          natalia,
          at: DateTime.now().subtract(const Duration(hours: 1)),
          link: meet,
        ),
        throwsA(isA<ValidationFailure>()),
      );
      expect(
        () => r.scheduleMeeting(natalia, at: nextWeek, link: 'el martes'),
        throwsA(isA<ValidationFailure>()),
      );
      expect(
        () => r.markMeetingDone(natalia),
        throwsA(isA<ValidationFailure>()),
      );
      await r.scheduleMeeting(natalia, at: nextWeek, link: meet);
      var c = await caseOf(natalia);
      expect(c.stage, CaseStage.meetingScheduled);
      expect(c.meetingLink, meet);
      expect(c.meetingConfirmed, isFalse);
      expect(await r.watchMyNewCases().first, 1);

      await r.markMeetingDone(natalia);
      expect((await caseOf(natalia)).stage, CaseStage.meetingDone);
      await r.setSitterApproval(natalia, approve: true);
      expect(
        (await r.fetchPendingSitters()).any((p) => p.user.id == natalia),
        isFalse,
      );
      expect(
        (await r.fetchAdminActions()).map((a) => a.action),
        containsAll(['schedule_meeting', 'meeting_done', 'approve_sitter']),
      );
    },
  );

  test('el cuidador confirma su asistencia', () async {
    await r.signOut();
    await r.signUp(
      email: 'conf@t.test',
      password: 'secreto1',
      fullName: 'Cata Confirma',
      role: UserRole.sitter,
      acceptedTerms: true,
    );
    final me = r.currentProfile!.id;
    expect(() => r.confirmMeeting(), throwsA(isA<ValidationFailure>()));
    await as('admin@doggo.app');
    await r.scheduleMeeting(me, at: nextWeek, link: meet);
    await as('conf@t.test', 'secreto1');
    await r.confirmMeeting();
    expect((await r.watchMyCase().first)?.meetingConfirmed, isTrue);
  });

  test(
    'solo quien lleva el caso o el superadmin actúan; el superadmin reasigna',
    () async {
      await as('superadmin@doggo.app');
      final owner = (await r.searchUsers(query: 'dueno@doggo.app')).single;
      await r.setAdmin(owner.id, makeAdmin: true);
      await as('dueno@doggo.app');
      expect(
        () => r.scheduleMeeting(natalia, at: nextWeek, link: meet),
        throwsA(isA<ValidationFailure>()),
      );
      expect(
        () => r.setSitterApproval(natalia, approve: true),
        throwsA(isA<ValidationFailure>()),
      );
      expect(
        () => r.reassignCase(natalia, owner.id),
        throwsA(isA<ValidationFailure>()),
      );
      await as('superadmin@doggo.app');
      await r.reassignCase(natalia, owner.id);
      expect((await caseOf(natalia)).assignedAdminName, 'Daniela Dueña');
      await as('dueno@doggo.app');
      await r.scheduleMeeting(natalia, at: nextWeek, link: meet);
    },
  );

  test('certificados: opcionales, PDF o imagen ≤ 10 MB, máximo 10; los ve el admin', () async {
    await r.signOut();
    await r.signUp(
      email: 'docs@t.test',
      password: 'secreto1',
      fullName: 'Dora Docs',
      role: UserRole.sitter,
      acceptedTerms: true,
    );
    final me = r.currentProfile!.id;
    await r.uploadMyDocument(
      kind: SitterDocKind.certificate,
      fileName: 'curso.pdf',
      bytes: Uint8List.fromList([1, 2, 3]),
    );
    expect(
      () => r.uploadMyDocument(
        kind: SitterDocKind.other,
        fileName: 'virus.exe',
        bytes: Uint8List(10),
      ),
      throwsA(isA<ValidationFailure>()),
    );
    expect(
      () => r.uploadMyDocument(
        kind: SitterDocKind.other,
        fileName: 'grande.pdf',
        bytes: Uint8List(maxSitterDocBytes + 1),
      ),
      throwsA(isA<ValidationFailure>()),
    );
    for (var i = 1; i < maxSitterDocs; i++) {
      await r.uploadMyDocument(
        kind: SitterDocKind.firstAid,
        fileName: 'foto$i.png',
        bytes: Uint8List(5),
      );
    }
    expect(
      () => r.uploadMyDocument(
        kind: SitterDocKind.other,
        fileName: 'once.pdf',
        bytes: Uint8List(5),
      ),
      throwsA(isA<ValidationFailure>()),
    );
    final docs = await r.fetchMyDocuments();
    expect(docs, hasLength(maxSitterDocs));
    await r.deleteMyDocument(docs.last.id);
    expect(await r.fetchMyDocuments(), hasLength(maxSitterDocs - 1));

    await as('admin@doggo.app');
    final mine = (await r.fetchPendingSitters()).singleWhere(
      (p) => p.user.id == me,
    );
    expect(mine.documents.first.fileName, 'curso.pdf');
    final url = await r.documentUrl(mine.documents.first);
    expect(url.data?.mimeType, 'application/pdf');

    await as('dueno@doggo.app');
    expect(
      () => r.documentUrl(mine.documents.first),
      throwsA(isA<ValidationFailure>()),
    );
  });
}
